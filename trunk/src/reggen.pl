#! /usr/bin/perl -w 


use XML::Parser;
use IO::File;
use Getopt::Long;

my ($DEBUG, $input, $on_screen);
my $output;

GetOptions( 'debug!'   => \$DEBUG,
	    'input=s'  => \$input,
	    'screen!'  => \$on_screen);

# ------------------------------
#   check input file
# ------------------------------
if ( ! defined $input ) {
    die "Please specify ONE xml file!\n";
}
elsif ( ! -f $input ) {
    die "Bad file: \"$input\"!\n";
}

# ------------------------------
#   variables used during
#   parsing XML file
# ------------------------------
my @stack;
my $content;
my @scope_tag = ( "global", "field");
my %global    = ();  # opt -> valut
my %field     = ();
my $field_cnt = 0;

# ------------------------------
#  Result HASH after parsing
#  XML configuration file
# ------------------------------
my @register;
my %register  = (); # name => (addr  => 00f3,    # address in hex format
		    #          field => @fields  # array contains %field,
		    #          wr    => 1/0      # this register can be written by SW or not,
		    #          line  => @line)   # address bits need to be decoded in discrete address mode 

# ------------------------------
#   Log file
# ------------------------------
my $time = `date +%Y%m%d%H%M%S`;
chomp $time;
my $log_file = new IO::File "> reggen_$time.log";
if ( ! defined $log_file ) {
    warn "Can not open log file!\n";
    $log_file = "";
}

# ------------------------------
#   Parse XML file using
#   XML::Parser
# ------------------------------
my $p = new XML::Parser(Handlers => {Init    => \&init,
				     XMLDecl => \&xml_decl,
				     Start   => \&start,
				     End     => \&end,
				     Char    => \&char});

print "Parsing XML file...";
print $log_file "----------------------------------------\n";
print $log_file "         Parsing XML file\n";
print $log_file "----------------------------------------\n";
$p->parsefile($input, ErrorContext => 3);
my $reg_msb  = $global{reg_width}-1;
my $addr_msb = $global{addr_width}-1;
print "done!\n";

print "Select output destination...";
print $log_file "\n";
print $log_file "----------------------------------------\n";
print $log_file "      Select output destination\n";
print $log_file "----------------------------------------\n";
if ( $on_screen ) {
    print $log_file "Code will be dumped on screen, be carefull!\n";
    $output = "STDOUT";
    print "Screen\n";
}
else {
    print $log_file "Source code is in $global{module}.vp\n";
    $output = new IO::File "> $global{module}.vp";
    if ( ! defined $output ) {
	die "Can not open \"$output\" for write!\n";
    }
    print "$global{module}.vp\n";
}

# ------------------------------
#   Body
# ------------------------------
print "Allocating address...";
print $log_file "\n";
print $log_file "----------------------------------------\n";
print $log_file "          Allocating address\n";
print $log_file "----------------------------------------\n";
&allocat_address;
print "done!\n";


# ------------------------------
#   Output code
# ------------------------------
&output_code;

# ------------------------------
#   Close file
# ------------------------------
$log_file->close();
$output->close();


# ------------------------------
#   Overwirte input file
#   as result file
# ------------------------------
my $result_file = new IO::File  "> $input";
if ( ! defined $result_file ) {
    warn "Can not overwrite input file \'$input\' to save result.";
    exit;
} else {
    &save_result($result_file);
    $result_file->close();
}


sub output_code {
    print $output '&ModuleBeg;', "\n";
    print $output '&Ports;', "\n";
    print $output '&Regs;', "\n";
    print $output '&Wires;', "\n";
    print $output "\n";
    print $output "/****************************************\n";
    print $output " INPUT PORTS\n";
    print $output " ===========\n";
    print $output "  $global{clock}\n";
    print $output "  $global{reset}\n";
    print $output "  addr[$addr_msb:0]\n";
    print $output "  wdata[$reg_msb:0]\n";
    print $output "  wr_en\n";
    print $output "  rd_en\n";
    print $output " \n";
    print $output " OUTPUT PORTS\n";
    print $output " ============\n";
    print $output "  rdata[$reg_msb:0]\n";
    print $output "  rd_ack\n";
    print $output " \n";
    print $output "*****************************************/\n";
    
    

    print "Generating Decoder...";
    print $log_file "\n";
    print $log_file "----------------------------------------\n";
    print $log_file "        Generate Decoder\n";
    print $log_file "----------------------------------------\n";
    &g_decoder_code($output);
    print "done!\n";
    
    print "Generating register controller...";
    print $log_file "\n";
    print $log_file "----------------------------------------\n";
    print $log_file "        Generate Controller\n";
    print $log_file "----------------------------------------\n";
    foreach my $name( keys %register ) {
	print $log_file "Generating code for $name, address is ${$register{$name}}{addr}.\n";
	foreach ( @{${$register{$name}}{field}} ) {
	    my %singel_field = @{$_};
	    print $log_file "  Field [$singel_field{msb}:$singel_field{lsb}], $singel_field{name}\n";
	    &g_ctrl_code($output, $global{clock}, $global{reset}, ${$register{$name}}{addr}, %singel_field);
	}
	print $log_file "\n";
    }
    print "done!\n";

    print "Grouping fields to register...";
    print $log_file "\n";
    print $log_file "----------------------------------------\n";
    print $log_file "      Group fields to register\n";
    print $log_file "----------------------------------------\n";
    &g_reg_group_code($output);
    print "done!\n";

    print $output "\n", '&ModuleEnd;', "\n";
}

sub init {
    print $log_file "Start Parsing \"$input\", ";
}

sub xml_decl {
    my ($expat, $version, $encoding, $standalone) = @_;

    print $log_file "XML version $version\n";
}

sub start {
    my ($expat, $element) = @_;
    
    push @stack, $element if &is_scope_tag($element);

    $content = "";
}

sub end {
    my ($expat, $element) = @_;

    my $cur_scope = $stack[$#stack];

    if ( $cur_scope eq $element ) {
	&{$element};
    }
    else {
	eval "\$$cur_scope\{$element\} = ". '$content' . ";";
    }

    pop @stack if &is_scope_tag($element);
}

sub char {
    my ($expat, $str) = @_;

    if ( $str !~ /^[ \t\n]+$/ ) {
	$content = $content . $str;
    }
}

sub is_scope_tag {
    my $tag = $_[0];

    foreach ( @scope_tag ) {
	return 1 if $tag eq $_;
    }
    
    return 0;
}

sub global {
    if ($DEBUG) {
	print "\nGlobal\n";
	foreach (keys %global) {
	    print "$_: $global{$_}\n";
	}
    }
}

sub field {
    if ($DEBUG) {
	print "\nField: $field{name}\n";
	foreach ( keys %field) {
	    print "$_: $field{$_}\n";
	}
    }

    &check_field;

    if ( $register{$field{r_name}} ) {
	if ( ${$register{$field{r_name}}}{addr} ne $field{r_addr} ) {
	    warn "**Address confict on \"$field{r_name}\", last setting wins!\n";
	}
	${$register{$field{r_name}}}{addr} = $field{r_addr};
	$field_cnt++;
    }
    else {
	push @register, $field{r_name};
	${$register{$field{r_name}}}{addr} = $field{r_addr};
	$field_cnt = 0;
    }
	
    push @{${${$register{$field{r_name}}}{field}}[$field_cnt]}, %field;
    if ( $field{st} eq "rw" || $field{st} eq "rw1c" ) {
	${$register{$field{r_name}}}{wr} = 1;
    }

    %field = ();
}

sub g_ctrl_code {
    my $output_file = shift @_;
    my $clk_name = shift @_;
    my $rst_name = shift @_;
    my $addr     = shift @_;
    my %field      = @_;

    my $rst_code = ""; 
    my $clk_code = "";
    my $out_code = "";

    # ------------------------------
    #   note
    # ------------------------------
    my @note = ();
    if ( $field{note} ) {
	push @note, split(/\n/,  $field{note} ); 
    }
    $note = join "\n//  ", @note;
    $note = "//  " . $note;

    # ------------------------------
    #   reset code
    # ------------------------------
    if ( $field{width} == 1 ) {
	$rst_code = "$field{name} <= $field{rstv};\n";
    }
    else {
	$rst_code = $field{name} . "[" . ($field{width}-1) . ":0] <= $field{rstv};";
    }

    # ------------------------------
    #   clock code
    # ------------------------------
    my @clk_code = ();

    my @hw_code = ();
    my @sw_code = ();
    my @el_code = ();

    if ( ($field{ht} eq "sbf" || $field{ht} eq "cbf" || $field{st} eq "rw1c") && 
	 ($field{width} > 1 ) ) {
	# bitwise 
	for ( my $i = 0; $i < $field{width}; $i++ ) {
	    push @hw_code, &{$field{ht}}( $field{name}, $field{hc}, $field{hv}, $field{width}, $i );
	    push @sw_code, &{$field{st}}( $field{name}, $addr, $field{width}, $field{msb}, $field{lsb}, $i, 1 );
	    push @el_code, "$field{name}\[$i\] <= $field{name}\[$i\];\n";
	}
    }
    else {
	push @hw_code, &{$field{ht}}( $field{name}, $field{hc}, $field{hv}, $field{width} );
	push @sw_code, &{$field{st}}( $field{name}, $addr, $field{width}, $field{msb}, $field{lsb} );
	if ( $field{width} > 1 ) {
	    push @el_code, $field{name} . "[" . ($field{width}-1) . ":0] <= " . $field{name} . "[" . ($field{width}-1) . ":0];\n";
	}
	else {
	    push @el_code, "$field{name} <= $field{name};\n";
	}
    }

    if ( $field{ht} eq "ro" ) {
	foreach (@sw_code) {
	    push @clk_code, $_;
	    push @clk_code, "else " . (shift @el_code);
	}
    }
    elsif ( $field{ht} eq "hw" ) {
	foreach (@hw_code) {
	    push @clk_code, $_;
	}
    }
    elsif ( $field{st} eq "ro" ) {
	foreach (@hw_code) {
	    push @clk_code, $_;
	    push @clk_code, "else " . (shift @el_code);
	}
    }
    elsif ( $field{swd} ) {
	foreach (@sw_code) {
	    push @clk_code, $_;
	    push @clk_code, "else " . (shift @hw_code);
	    push @clk_code, "else " . (shift @el_code);
	}
    }
    else {
	foreach (@hw_code) {
	    push @clk_code, $_;
	    push @clk_code, "else " . (shift @sw_code);
	    push @clk_code, "else " . (shift @el_code);
	}
    }

    $clk_code = join "\n     ", @clk_code;

    # ------------------------------
    #   output code
    # ------------------------------
    my @out_code = ();

    if ( $field{output} ) {
	if ( $field{width} > 1 ) {
	    push @out_code, "assign $field{output}\[" . ($field{width}-1) . ":0] = $field{name}\[" . ($field{width}-1) . ":0];"; 
	}
	else {
	    push @out_code, "assign $field{output} = $field{name};";
	}
    }

    $out_code = join "\n", @out_code;

    # ------------------------------
    #   Output Code
    # ------------------------------
    print $output_file "\n";
    print $output_file "// --------------------------------------------------\n";
    print $output_file "$note\n";
    print $output_file "// --------------------------------------------------\n";
    print $output_file "always \@(posedge $clk_name or negedge $rst_name)\n";
    print $output_file "  if (~$rst_name) begin\n";
    print $output_file "     $rst_code\n";
    print $output_file "  end\n";
    print $output_file "  else begin\n";
    print $output_file "     $clk_code\n";
    print $output_file "  end\n";
    print $output_file "$out_code\n";
    print $output_file "\n";
}



# Hardware Access Type
sub sbf {
    my ($name, $hc, $hv, $width, $index) = @_;

    if ( $width > 1 ) {
	return "if ( $hc\[$index\] ) $name\[$index\] <= 1'b1;";
    }
    else {
	return "if ( $hc ) $name <= 1'b1;";
    }
}

sub cbf {
    my ($name, $hc, $hv, $width, $index) = @_;
    
    if ( $width > 1 ) { 
	return "if ( $hc\[$index\] ) $name\[$index\] <= 1'b0;";
    }
    else {
	return "if ( $hc ) $name <= 1'b0;";
    }
}

sub sv { 
    my ($name, $hc, $hv, $width) = @_;

    if ( $width > 1 ) {
	return "if ( $hc ) $name\[" . ($width-1) . ":0] <= $hv\[" . ($width-1) . ":0];";
    }
    else {
	return "if ( $hc ) $name <= $hv;";
    }
}

sub hw {
    my ($name, $hc, $hv, $width) = @_;
    
    if ( $width > 1 ) {
	return "$name\[" . ($width-1) . ":0] <= $hv\[" . ($width-1) . ":0];";
    }
    else {
	return "$name <= $hv;";
    }
}

sub ro {
}



# Software Access Type
sub rw {
    my ($name, $reg_addr, $width, $msb, $lsb, $index, $bw) = @_;
    
    if ( $bw ) {
	return "if ( swwr_$reg_addr ) $name\[$index\] <= wdata\[" . ($lsb+$index) . "];";
    }
    elsif ( $width > 1 ) {
	return "if ( swwr_$reg_addr ) $name\[" . ($width-1) . ":0] <= wdata\[$msb:$lsb\];";
    }
    else {
	return "if ( swwr_$reg_addr ) $name <= wdata\[$lsb\];";
    }
}

sub rc {
    my ($name, $reg_addr, $width, $msb, $lsb, $index, $bw) = @_;

    if ( $bw ) {
	return "if ( swrd_$reg_addr ) $name\[$index\] <= 1'b0;";
    }
    elsif ( $width > 1 ) {
	return "if ( swrd_$reg_addr ) $name\[" . ($width-1) . ":0] <= $width\'h0;";
    }
    else {
	return "if ( swrd_$reg_addr ) $name <= 1'b0;";
    }
}

sub rw1c {
    my ($name, $reg_addr, $width, $msb, $lsb, $index) = @_;
    if ( $width > 1 ) {
	return "if ( wdata\[" . ($lsb + $index) . "\] && swwr_$reg_addr ) $name\[$index\] <= 1'b0;";
    }
    else {
	return "if ( wdata\[$lsb\] && swwr_$reg_addr ) $name <= 1'b0;";
    }
}

sub g_reg_group_code {
    my ($output_file) = @_;
    
    print $output_file "// Group fields into registers\n";
    foreach (@register) {
	print $log_file "Grouping fields in $_\n";
	my $addr = ${$register{$_}}{addr};

	print $output_file "// $_\n";
	print $output_file '&CombBeg;', "\n";
	print $output_file "reg_$addr\[$reg_msb:0] = $global{reg_width}\'d0;\n";
	foreach ( @{${$register{$_}}{field}} ) {
	    my %field = @{$_};
	    print $log_file "  Field $field{name}\n";
	    print $output_file "reg_$addr\[$field{msb}\:$field{lsb}] = $field{name}\[", $field{width}-1, ":0];\n";
	}
	print $log_file "\n";
	print $output_file '&CombEnd;', "\n\n";
    }
}

sub g_decoder_code { 
    my ($output_file) = @_;
    
    print $log_file "Generating SW select signal decoder, ";
    print $output_file "\n// Register select signals\n";

    if ( $global{addr_type} =~ /^discrete$/i ) {
	print $log_file "\"assign\" mode decoder for discrete address.\n";
	foreach ( @register ) {
	    print $output_file "assign swsel_${$register{$_}}{addr} = " . (join ' & ', @{${$register{$_}}{line}} ) . ";\n";
	}
	print $output_file "\n";
    }
    else {
	print $log_file "\"case\" mode decoder for continous/custom address.\n";
	print $output_file '&CombBeg;', "\n";
	foreach ( @register ) {
	    print $output_file "swsel_${$register{$_}}{addr} = 1'b0;\n";
	}
	print $output_file "case ( addr[", $global{eff_width}-1, ":0] ) // synthesis parallel_case\n";
	foreach ( @register ) {
	    print $output_file "$global{eff_width}\'h${$register{$_}}{addr}: swsel_${$register{$_}}{addr} = 1'b1;\n";
	}
	print $output_file "default: ;\n";
	print $output_file "endcase\n";
	print $output_file '&CombEnd;', "\n";
	print $output_file "\n";
    }

    print $log_file "Generating Flip-Flop for swwr and swrd signals...\n";
    print $output_file "\n// Flop RD/WR control signal\n";
    print $output_file "always \@( posedge $global{clock} or negedge $global{reset} )\n";
    print $output_file "  if ( ~$global{reset} ) begin\n";
    foreach ( @register ) {
	print $output_file "    swrd_${$register{$_}}{addr} <= 1'b0;\n";
	if ( ${$register{$_}}{wr} ) {
	    print $output_file "    swwr_${$register{$_}}{addr} <= 1'b0;\n";
	}
    }
    print $output_file "  end\n";
    print $output_file "  else begin\n";
    foreach ( @register ) {
	print $output_file "    swrd_${$register{$_}}{addr} <= swsel_${$register{$_}}{addr};\n";
	if ( ${$register{$_}}{wr} ) {
	    print $output_file "    swwr_${$register{$_}}{addr} <= swsel_${$register{$_}}{addr} & wr_en;\n";
	}
    }
    print $output_file "  end\n";
    print $output_file "\n";

    print $log_file "Generating read MUX and Flip Flop...\n";
    print $output_file "// Read MUX\n";
    print $output_file '&CombBeg;', "\n";
    print $output_file "case ( 1'b1 ) // synthesis parallel_case\n";
    foreach ( @register ) {
	print $output_file "swrd_${$register{$_}}{addr}: reg_sel[$reg_msb:0] = reg_${$register{$_}}{addr}\[$reg_msb:0];\n";
    }
    print $output_file "default: reg_sel[$reg_msb:0] = $global{reg_width}\'d0;\n";
    print $output_file "endcase\n";
    print $output_file '&CombEnd;', "\n\n";
    
    print $output_file "// Flop out read data and read ACK\n";
    print $output_file "always \@(posedge $global{clock} or negedge $global{reset} )\n";
    print $output_file "  if ( ~$global{reset} ) begin\n";
    print $output_file "    rdata[$reg_msb:0] <= $global{reg_width}\'d0;\n";
    print $output_file "    rd_ff  <= 1'b0;\n";
    print $output_file "    rd_ack <= 1'b0;\n";
    print $output_file "  end\n";
    print $output_file "  else begin\n";
    print $output_file "    rdata[$reg_msb:0] <= reg_sel[$reg_msb:0];\n";
    print $output_file "    rd_ff  <= rd_en;\n";
    print $output_file "    rd_ack <= rd_ff;\n";
    print $output_file "  end\n";
    print $output_file "\n";
}

sub allocat_address {
    my $reg_cnt  = @register;

    if ( $global{addr_type} =~ /^discrete$/i ) {
	my $hot_bits = &hot_bit_needed($reg_cnt, $global{addr_width});
	if ( ! $hot_bits ) {
	    die "Discrete address in $global{addr_width} bits address is not enough for $reg_cnt registers, use \"continue\" address type or enlarge address width!\n\n";
	}
	else {
	    print $log_file "Discrete address allocated, use $hot_bits hot bit(s).\n";
	    &g_discrete_addr($hot_bits, $global{addr_width});
	}
    }
    elsif ( $global{addr_type} =~ /^continue$/i ) {
	print $log_file "Continous address allocated.\n";
	$global{eff_width} = &calc_eff_addr_width($reg_cnt);
	&g_continue_addr($global{addr_width});
    }
    elsif ( $global{addr_type} =~ /^auto$/i ) {
	my $hot_bits  = &hot_bit_needed($reg_cnt, $global{addr_width} );
	my $eff_width = &calc_eff_addr_width($reg_cnt);
	
	if ( $hot_bits < $eff_width ) {
	    print $log_file "Discrete address allocated, use $hot_bits hot bit(s).\n";
	    &g_discrete_addr($hot_bits, $global{addr_width});
	    $global{addr_type} = 'discrete';
	}
	else {
	    print $log_file "Continous address allocated.\n";
	    &g_continue_addr($global{addr_width});
	    $global{addr_type} = 'continue';
	    $global{eff_width} = $eff_width;
	}
    }
    elsif ($global{addr_type} =~ /^custom$/i ) {
	print $log_file "Use customized address.\n";
	$global{eff_width} = $global{addr_width};
    }
    else {
	die "Unsupported addres type: \"$global{addr_type}\".\n";
    }

    foreach (@register) {
	print $log_file "${$register{$_}}{addr} $_\n";
    }
}


sub hot_bit_needed {
    my ($reg_cnt, $addr_width) = @_;

    my $hot_bits; 

    for ($hot_bits = 1; $hot_bits < $addr_width/2 + 1; $hot_bits++ ) {
	return $hot_bits if &C($addr_width, $hot_bits) >= $reg_cnt;
    }

    return 0;
}

sub C {
    my ($base, $cnt) = @_;

    my ($product, $divider) = (1, 1);

    for (my $i=0; $i<$cnt; $i++) {
	$product = $product * ($base-$i);
    }

    for (my $i=$cnt; $i>0; $i--) {
	$divider = $divider * $i;
    }

    return $product/$divider;
}

sub g_discrete_addr {
    my ($num_of_hot_bits, $b_width) = @_;
    my $round = 0;
    my @hot_bit;

    my $h_width = &bwth2hwth($b_width);

    for (my $i=0; $i<$num_of_hot_bits; $i++) {
	$hot_bit[$i] = $num_of_hot_bits - 1 - $i;
    }

    foreach ( @register ) {
	my $addr = 0;
	foreach (@hot_bit) {
	    $addr = $addr + (2 ** $_);
	}
	my $addr_s = sprintf('%0*2$x', $addr, $h_width);

	${$register{$_}}{addr} = $addr_s;
	my @line = map {"addr[$_]"} @hot_bit;
	# push @{${$register{$_}}{line}}, @hot_bit;
	push @{${$register{$_}}{line}}, @line;


	if ( $hot_bit[$#hot_bit] == $b_width - $num_of_hot_bits ) {
	    $round++;
	    for ( my $i=0; $i<$num_of_hot_bits; $i++) {
		$hot_bit[$i] = $round + $num_of_hot_bits - 1 - $i;
	    }
	}
	else {
	    foreach (@hot_bit) {
		if ( $_ < $b_width-1 ) {
		    $_++;
		    last;
		}
	    }
	}
    }
}

sub g_continue_addr {
    my ($b_width) = @_;

    my $h_width = &bwth2hwth($b_width);

    my $addr = 0;
    my $addr_s = "";

    foreach ( @register ) {
	$addr_s = sprintf('%0*2$x', $addr, $h_width);
	${$register{$_}}{addr} = $addr_s;
	$addr++;
    }
}

sub calc_eff_addr_width {
    my ($reg_cnt) = @_;
    my $addr_width = (log $reg_cnt) / (log 2);

    if ( int $addr_width < $addr_width ) {
	return (int $addr_width) + 1;
    }
    else {
	return (int $addr_width);
    }
}
    

sub bwth2hwth {
    if ( $_[0] % 4 ) {
	return ((int $_[0] / 4) + 1);
    }
    else {
	return (int $_[0] / 4);
    }
}

sub check_field {
    if ( $field{ht} eq "hw" && ! $field{hv} ){
	print "**Error: Register: $field{r_name}, Field: $field{name}\n";
	die "ht is \"hw\", but no value interface (hv) specified.\n";
    }

    if ( $field{ht} eq "hw" && $field{st} ne "ro" ) {
	print "**Warnig: Register: $field{r_name}, Field: $field{name}\n";
	warn "ht is \"hw\", but st is not \"ro\", setting on st will be converted to \"ro\".\n";
    }
    
    if ( $field{ht} eq "ro" && ($field{hc} || $field{hc}) ) {
	print "**Warning: Register: $field{r_name}, Field: $field{name}\n";
	warn "ht is \"ro\", any setting on hc or hv will be ignored.\n";
    }
}

sub save_result {
    my ($result_file) = @_;

    print $result_file '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', "\n";
    print $result_file "<global>\n";
    print $result_file "<module>$global{module}</module>\n";
    print $result_file "<reg_width>$global{reg_width}</reg_width>\n";
    print $result_file "<addr_width>$global{addr_width}</addr_width>\n";
    print $result_file "<clock>$global{clock}</clock>\n";
    print $result_file "<reset>$global{reset}</reset>\n";
    print $result_file "<addr_type>$global{addr_type}</addr_type>\n";
    
    foreach (@register) {
	my $r_name = $_;
	my $r_addr = ${$register{$_}}{addr};

	my @fields = @{${$register{$_}}{field}};
	foreach (@fields) {
	    my %single_field = @{$_};
	    print $result_file "<field>\n";
	    print $result_file "<r_name>$r_name</r_name>\n";
	    print $result_file "<r_addr>$r_addr</r_addr>\n";
	    print $result_file "<name>$single_field{name}</name>\n";
	    print $result_file "<width>$single_field{width}</width>\n";
	    print $result_file "<msb>$single_field{msb}</msb>\n";
	    print $result_file "<lsb>$single_field{lsb}</lsb>\n";
	    print $result_file "<swd>$single_field{swd}</swd>\n";
	    print $result_file "<rstv>$single_field{rstv}</rstv>\n";
	    print $result_file "<note>$single_field{note}</note>\n";
	    print $result_file "<ht>$single_field{ht}</ht>\n";
	    if ( $single_field{hv} ) {
		print $result_file "<hv>$single_field{hv}</hv>\n";
	    } else {
		print $result_file "<hv/>\n";
	    }
	    if ( $single_field{hc} ) {
		print $result_file "<hc>$single_field{hc}</hc>\n";
	    } else {
		print $result_file "<hc/>\n";
	    }
	    print $result_file "<st>$single_field{st}</st>\n";
	    if ( $single_field{output} ) {
		print $result_file "<output>$single_field{output}</output>\n";
	    } else {
		print $result_file "<output/>\n";
	    }
	    print $result_file "</field>\n";
	}
    }
    
    print $result_file "</global>\n";
}

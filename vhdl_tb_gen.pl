#!/usr/bin/perl
use strict;
use warnings;

use v5.14;

use Cwd;

=pod

=head1 ########################################
# VHDL Testbench Generation            #
########################################

This script can generate a VHDL testbench file based upon the VHDL source code
name provided.

=cut

#TEMP
my $fileName = shift;

die "Must import a VHDL source file!\n" unless ($fileName =~ m/.*.vhd/i);

open (my $srcCodeFH, '<', $fileName) or 
  die "Couldn't find the VHDL source code with the given file name!\n";

my @srcCode     = <$srcCodeFH>;
my $entityName  = "";
my $packageName = "";
my @entityBody  = ();
my @ioList      = ();
my $ioClock     = "";
my $ioReset     = "";

# First, find the entity name cause it should be unique.
my $copyEn      = 0;

foreach (@srcCode) {
  # Find entity name
  if (/^(\s*entity\s*) (\S+) (\s*is\s*$)/ix) {
    $entityName = $2;
    $copyEn = 1;
  }
  
  # Preserve the entity body
  if ($copyEn and (not /^\s*--\s*/)) {
    if (/;/) {
      $_ =~ s/(\s*:=[^;]*;)|(;\s*--\s*[nN][rR].*)/;/;
    } else {
      $_ =~ s/(\s*:=.*)//;
    }
    push (@entityBody, $_);
  }
  
  # Search the package 
  if (/^\s*package\s*($entityName)_pkg\s*is$/) {
    $packageName = "$entityName".'_pkg';
  }
  
  if (/^\s*end\s+$entityName\s*;/x) {
    $copyEn = 0;
  }
}

close $srcCodeFH;

# Second, create I/O list from the entity body
if ((scalar @entityBody) == 0) {
  die "Couldn't find the entity!\n";
} else {
  foreach (@entityBody) {
    next unless /([a-zA-Z0-9_]+)\s*:\s*(in|out|inout)\s*([^;]+);/i;
    my $sigName = $1;
    my $sigDir  = $2;
    my $sigType = $3;
    # Try to find the module clock
    if ($sigName =~ m?.*(clk|clock).*?i and $sigDir =~ m/in/i and $sigType =~ m/std_logic/i) {
      $ioClock = $sigName;
    } elsif ($sigName =~ m?.*(rst|reset).*?i and $sigDir =~ m/in/i and $sigType =~ m/std_logic/i) {
      $ioReset = $sigName; 
    } else {
      push (@ioList, [$sigName, $sigDir, $sigType]);
    }
  }
}

# last, spit out the TB file
open (my $tbCodeFH, '>', $entityName."_tb.vhd") or 
  die "Couldn't create testbench file!\n";
  
select $tbCodeFH;

# print Copyright
print  <<FileHeader;
--------------------------------------------------------------------------------
-- COPYRIGHT (c) 2017 Schweitzer Engineering Laboratories, Inc.
-- SEL Confidential
--
-- Description: Testbench for the $entityName component
--
-- NR = Not Registered
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

FileHeader

# Print srouce package if there is one found
print "use work.$packageName.all\n\n" unless $packageName eq "";

# Print entity
print <<TestbenchEntity;
entity $entityName\_tb is 
generic
(
  -- Testbench generic(s) here
  
);
end entity tb of $entityName\_tb;

TestbenchEntity

# Print start of the architecture
print "architecture tb of $entityName\_tb is\n\n";

# Print UUT component declaration if needed
if ($packageName eq "") {
  foreach my $string (@entityBody) {
    $string =~ s/entity\s*$entityName\s*is/component $entityName/;
    $string =~ s/\s*end(.*)/end component;\n\n/;
    chomp($string);
    print "  $string\n";
  } 
}

print "  -- Constant declaration(s) here\n";
print "  constant TB_FREQ : integer := 1e3; -- Hz\n";
print "  constant CLK_CYC : integer := 1e9 ns/TB_FREQ; -- ns\n\n";

print "  -- UUT signals\n";

print "  signal $ioClock : std_logic : '0';\n" unless $ioClock eq "";
print "  signal $ioReset : std_logic : '0';\n" unless $ioReset eq "";
foreach my $string (@ioList) {
  # Append initialization for inputs otherwise "NR" for outputs
  if ((@$string[1] eq 'in') or (@$string[1] eq 'inout')) {
    if (@$string[2] =~ m/std_logic\b/i) {
      print "  signal @$string[0] : @$string[2] := '0';\n";
    } elsif (@$string[2] =~ m/std_logic_vector.+/i) {
      print "  signal @$string[0] : @$string[2] := (others => '0');\n";
    } 
  } else {
     print "  signal @$string[0] : @$string[2] -- NR;\n";
  } 
}
print "\n";

print "  -- Other signal declaration(s) here\n";
print "  signal sim_done : boolean := false;\n\n";

# Start the architecture
print "begin\n\n";

# Print the UUT instantiation
print "  -- UUT\n";
foreach my $string (@entityBody) {
  $string =~ s/\b([a-zA-Z0-9_]+)(\s*):(.*;$)/$1$2 => $1,/;
  $string =~ s/\b([a-zA-Z0-9_]+)(\s*):(.*$)/$1$2 => $1/;
  $string =~ s/entity\s*$entityName\s*is/uut: $entityName/;
  $string =~ s/\bport\b/port map/;
  $string =~ s/\s*end(.*)//;
  chomp($string);
  print "  $string\n";
} 

# Print Testbench clock generation and stimulus processes
$ioClock = '<UUT_CLOCK>' unless $ioClock ne "";
$ioReset = '<UUT_RESET>' unless $ioReset ne "";

print <<TestbenchClockGen;
  -- Clock Generation
  clk_gen_proc: process
  begin
    if (sim_done = false) then
      $ioClock  <= not $ioClock;
      wait for CLK_CYC/2;
    else
      wait;
    end if;
  end process clk_gen_proc;

TestbenchClockGen

print <<TestbenchStimulus;
  -- Stimulus Process
  stim_proc: process
  begin
    $ioReset <= '1';
    -- Simulus goes here
    -- ...
    -- 
    
    sim_done <= true;
    wait;
  end process stim_proc;

TestbenchStimulus

# Print end of the architecture
print "end tb;\n";

select STDOUT;

print "Success: finish creating a VHDL testbench called $entityName\_tb.vhd \n";
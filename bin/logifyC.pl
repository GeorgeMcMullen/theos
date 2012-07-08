#!/opt/local/bin/perl
#
# logifyC.pl - by George McMullen
#
# A script to convert C headers into Theos / MobileSubstrate function loggers. 
# A lot like logify.pl, but for C instead of Objective-C. Useful when you need to 
# figure out what is going on with OpenGL, CoreAudio, or other iOS C libraries.
#
# Requires Doug MacEachern's version 0.75 of C::Scan from 
# 	http://people.apache.org/~dougm/Scan.pm
# The previous version may work too, but there are no guarantees.
#
# Usage: logifyC.pl INFILE > OUTFILE
#
# *** WARNING ***
#
# No guarantees or warantees provided. It may miss a few function declarations
# if they are hidden deep in ifdefs and it may include some other function
# declarations that are not available on iOS. It may also mangle some functions
# here and there. If this happens, you may find that your library does not run
# at all or may even crash what your are trying to debug.
#

if ($#ARGV != 0)
{
  print "Usage: logifyC.pl INFILE > OUTFILE\n";
  exit;
}

if (! -f $ARGV[0])
{
  print "Error: $ARGV[0] not found\n";
  exit;
}

$TMPDIR="/tmp"; # Whereever a temporary file can live
$PID=$$; # The current process ID (to make a unique temporaray file

use File::Basename;
use C::Scan;

# Get the header's file name and remove the .h so we can use it in our definitions
$headerFileName=basename($ARGV[0]);
$headerFileName=~ s/\.h$//;

# Estimate the full path of the framework, from the given path
$headerFullPath=$ARGV[0];
$headerFullPath=~ s#\.framework/.*$##;
$headerFullPath=~ s#^.*/##;
$headerFullPath=$headerFullPath."/".basename($ARGV[0]);

# We are going to get rid of a whole bunch of stuff so that C::Scan has an easier time parsing it and output it to a temporary file.
# We don't really need to process the header file in all it's completeness, we just want to get any function names we can.
$processedHeader=$TMPDIR."/".$headerFileName."-$PID.h";

open (INFILE, $ARGV[0]); # Read in the file
@inFileArray = <INFILE>;
close(INFILE);

$inFile = join('',@inFileArray); # Make it a single line
$inFile =~ s#\/\*.*?\*\/##sg; # Get rid of multiline comments
$inFile =~ s#\\\s+\n##g; # Merge lines that end in a backslash with their next line
# For some reason C::Scan chokes on extern "C" { .* } so we'll get rid of it
if ($inFile =~ /extern.*\"C\"/)
{
  $inFile =~ s/.*extern.*\"C\".*\n.*{//i; # Sometimes the opening bracket is on the next line
  $inFile =~ s/.*extern.*\"C\".*{//i; # Sometimes it's on the same line
  $lastCurly = rindex($inFile, '}'); # Well get rid of the last bracket, hopefully it's the bracket that matches
  $inFile = substr($inFile, 0, $lastCurly-1).substr($inFile, $lastCurly);
}

@inFileArray = split(/\n/, $inFile); # We need to work with the file as an array again
open (OUTFILE, ">".$processedHeader); # Opening our TMP file for writing
for ($i=0; $i<$#inFileArray; $i++)
{
  $inFileArray[$i] =~ s#//.*##g; # Get rid of end of line comments
  $inFileArray[$i] =~ s/^#.*//ig; # Get rid of single line defines, includes, pragmas, and if style statements that start at the beginning of the line
  $inFileArray[$i] =~ s/^\s+#.*//ig; # Get rid of single line defines, includes, pragmas and if style statements that have a space in the beginning
  $inFileArray[$i] =~ s/\).*?__/\)\n__/; # For some reason C::Scan has problems detecting when a function has a compiler __attribute on the same line
  print OUTFILE $inFileArray[$i]."\n";
}
close(OUTFILE);


# We need a little documentation here about ignoring certain errors that come
# up when parsing a header file. Most of the time it means nothing and is
# because of the hack that needed to be in place in order to make C::Scan not
# follow the entire tree of includes. This comment block is added just in case
# you copy/paste the output by mistake.
print STDERR "/*\n";
print STDERR " *\n";
print STDERR " * Typically, you don't have to worry about the following errors regarding file not found for #includes.\n";
print STDERR " *\n";

# Scan the file using C::Scan
$c = new C::Scan(filename => $processedHeader,
                 add_cppflags => "-isysroot/nonexistant -fwhole-program"); # This is a hack so that it will ignore all the includes by setting the system root to a nonexistant directory. Otherwise, we get a huge list of all declarations from all the included headers.
my $fdeclsArrayRef = $c->get('fdecls'); # We use this instead of parsed_fdecls because we don't really want to parse everything and it will probably break on some undefined types.

print STDERR " *\n";
print STDERR " */\n";


# Loop through all of the parsed function declarations.
foreach my $line (@$fdeclsArrayRef)
{
  $line =~ s/\n/ /g; # Function declarations may come in multiple lines. Get rid of the multiple lines and replace with space
  $line =~ s/\s+/ /g; # Replace multiple spaces with a single space

  if ($line =~ /\(/)
  {
    $line =~ s/__attribute.*$/\;/;                # Get rid of any prepocessing stuff that might be at the end of the line.
    if ($line !~ /__IPHONE_NA/)			  # Don't add any lines that don't apply to iPhone
    {
      $line =~ s/__OSX_AVAILABLE.*$/\;/;   # This is usualy in OSX/iOS SDK headers to identify the minimum SDK versions required for the function.

      # Get the function name
      $functionName=$line;
      $functionName=~ s/\(.*$//g;
      $functionName= &trim($functionName);
      $functionName=~ s/^extern //; # We need to get rid of "extern" to work with MobileSubstrate
      $functionName=~ s/.*\s//; # This should get rid of the function type
  
      # Get the function parameter
      $functionParameters=$line;
      $functionParameters=~ s/.*\(//g;
      $functionParameters=~ s/\;//g;
      $functionParameters= &trim($functionParameters);
      $functionParameters= "(".$functionParameters;
  
      # Get the function type
      $functionType=$line;
      $functionType=~ s/\(.*$//g;
      $functionType=~ s/$functionName//;
      $functionType= &trim($functionType);
      $functionType=~ s/^extern //; # We need to get rid of "extern" to work with MobileSubstrate
  
      # Strip out the function parameters, getting rid of *s, splitting them out to separate parameters and then joining them back together
      $functionParametersStripped=$functionParameters;
      $functionParametersStripped=~ s/\(//g;
      $functionParametersStripped=~ s/\)//g;
      @functionParametersStrippedNaked=split(/\,/, $functionParametersStripped);
      
      for ($i=0; $i<=$#functionParametersStrippedNaked; $i++)
      {
        $thisParameter=$functionParametersStrippedNaked[$i];
        $thisParameter=trim($thisParameter);
        $thisParameter=~s/.*\s//;
        $thisParameter=~s/\*//;
        $thisParameter=trim($thisParameter);
        $functionParametersStrippedNaked[$i]=$thisParameter;
      }
      $functionParametersStripped=join(",", @functionParametersStrippedNaked);
  
      # Build the array of function declarations which will be used to print out the function overrides
      $functionArray[$#functionArray+1]=$line;
      $functionTypeArray[$#functionTypeArray+1]=$functionType;
      $functionNameArray[$#functionNameArray+1]=$functionName;
      $functionParametersArray[$#functionParametersArray+1]=$functionParameters;
      $functionParametersStrippedArray[$#functionParametersStrippedArray+1]=$functionParametersStripped;
    }
  }
}

print <<EOINTRO;
/*
 *
 * Generated by logifyC.pl by George McMullen (c) 2011
 *
 */

#include "substrate.h"
#import <CoreFoundation/CoreFoundation.h>

#import <$headerFullPath> // Insert the framework that you are injecting into here

EOINTRO

# Print out the function overrides
for ($i=0; $i<=$#functionArray; $i++)
{
  print "$functionTypeArray[$i] (*orig_$functionNameArray[$i])$functionParametersArray[$i];\n";
  print "$functionTypeArray[$i] my_$functionNameArray[$i]$functionParametersArray[$i]\n";
  print "{\n";
  print "  NSLog(@\"$functionNameArray[$i] called: \");\n";
  print "  return orig_$functionNameArray[$i]($functionParametersStrippedArray[$i]);\n";
  print "}\n";
  print "\n";
}

print "\n";
print "\n";
print "// Insert the name of the framework you are injecting into before LogInitialize\n";
print "__attribute__((constructor)) static void ${headerFileName}LogInitialize()\n";
print "{\n";
print "  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];\n";
print "  // Insert the name of the framework you are injecting into before Log\n";
print "  NSLog(@\"${headerFileName}Log loaded in: %@\", [[NSProcessInfo processInfo] processName]);\n";
print "\n";

# Start printing out the function hooks
for ($i=0; $i<=$#functionArray; $i++)
{
  print "  MSHookFunction((void *)&$functionNameArray[$i], (void *)&my_$functionNameArray[$i], (void **)&orig_$functionNameArray[$i]);\n";
}


print "\n";
print "  [pool release];\n";
print "}\n";

# Remove the temporary file
unlink($processedHeader);

# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($)
{
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}

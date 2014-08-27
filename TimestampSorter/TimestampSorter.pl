#!/usr/bin/perl

use warnings "all";
use strict;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use DateTime;
use Text::CSV;
use diagnostics -verbose;

sub galaxyTimestampToDateTime {
	my $timeString = $_[0];
	my $year = $_[1];
	#											    			$1-month								       $2-DOM			$3-hr		 $4-Min		  	$5-Sec
	$timeString =~ m/(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+0*?([0-3]?[0-9])\s+([0-2]?[0-9]):([0-5]?[0-9]):0*?([0-5]?[0-9])/;
	my %monthNames = qw (Jan 1 Feb 2 Mar 3 Apr 4 May 5 Jun 6 Jul 7 Aug 8 Sep 9 Oct 10 Nov 11 Dec 12);
	my $month = $monthNames{$1};
	unless (defined $month)	{#if month is undefined
		die $timeString."\n The above timestamp has an invalid month name. Please fix.\n";
	}
	
	my $dateTime = DateTime->new( year => $year, #galaxy time stamps don't have a friggin year, go figure!
	month => $month, day => $2,
	hour => $3,	minute => $4, second => $5,
	time_zone => 'floating', 
	);
	
	return $dateTime;
}

sub timeIndex
#Input: 2 DateTime Timestamps: TicketTime, DataTime
#Output: The amount of 15 minute timestamps between $ticket - $data, signed according to that math.
#makes sure to account for daylight savings, and ignores leap seconds.
{
	my $a = $_[0]->clone->set_time_zone('UTC')->set_time_zone('floating');
	my $b = $_[1]->clone->set_time_zone('UTC')->set_time_zone('floating');

	return ( $a->subtract_datetime_absolute($b)->in_units("seconds") / 900 );
}

sub timeCompare
#Input: 2 DateTime Timestamps: TicketTime, DataTime
#Output: The amount of 15 minute timestamps between $ticket - $data, signed according to that math.
#makes sure to account for daylight savings, and ignores leap seconds.
{
	my $a = $_[0]->clone->set_time_zone('UTC')->set_time_zone('floating');
	my $b = $_[1]->clone->set_time_zone('UTC')->set_time_zone('floating');

	my $compare = ( $a->subtract_datetime_absolute($b)->in_units("seconds") / 900 );
	
	if ($compare < 0 ) {return -1;}
	if ($compare == 0 ) {return 0;}
	if ($compare > 0 ) {return 1;}
}

#this subroutine takes the first line of a file, and returns the header
sub parseHead { 
	my $headerText = $_[0];
	my $csv = Text::CSV->new({ sep_char => ',' });
	$csv->parse($headerText);
	my @header = $csv->fields();
	
	return @header;
}

#this program should return a simple hash, header -> dataarray
#further converting to a hash -> hash ...etc is done later.
sub csvToRawHash {
	my $inputFile = $_[0];
	my $fileType = $_[1];
	open(my $data, '<', $inputFile) or die "Could not open '$inputFile' $!\n";
	
	###START Header Parsing###{
	my $line = <$data>;
	chomp $line;
	my @header;
	if ($fileType eq "constants") {
		@header = parseHead($line);	#stores ordered list of header names
	}
	elsif ($fileType eq "data") {
		#TODO: 	Header parsing function that extracts the AHU name, 
		#TODO:	and true pointname from the header, and pointnames.csv
		#TODO:	so things are named correctly. Or maybe even consider
		#TODO:	not even doing this now, and doing it on data retrieval
	}
	###Header Parsing END###}
	
	my %rawHash;
	foreach (@header) {
		if ( (length ($_) ) == 0) {	#this makes sure no empty columns are accepted in the hash
			next;
		}
		else {
			$rawHash{$_} = [];	#initializes blank array reference to be pushed into later
		}
	}
	
	my $csv = Text::CSV->new({ sep_char => ',' });
	
	while ($line = <$data>) {
		chomp $line;
	 
		if ($csv->parse($line)) {
			my @fields = $csv->fields();	#current data on current row
			for( my $i = 0; $i < scalar @header; $i++ ) {	#iterating over columns
				if ( (length ($header[$i])) == 0 ) { #this makes sure no data in empty header columns are accepted
					next;
				}
				else {
					push @{ $rawHash{$header[$i]} }, $fields[$i];	#e.g. push @{$data{"CCV1tb"}}, "PHT"
				}
			}
		}
		else {
			warn "Line could not be parsed: $line\nWOULD YOU LIKE TO TERMINATE PROGRAM?(Y/n)";
			if (<STDIN> =~ m/Y|y/) {
				die $!;
			}
		}
	}
	return %rawHash;
}
opendir DIR, "." or die $!; 
print "!!!!!NOTE: FOR THIS TO FUNCTION, YOUR TIMESTAMP COLUMNS MUST BE NAMED TT!!!!!\n";
print "Year of data?:";
our $year = <STDIN>;
chomp($year);
	
while (my $inputFile = readdir(DIR)) {
	if( ($inputFile !~ m/\.csv/)||($inputFile =~ m/_sort\.csv/) ) {#||($inputfile =~ m/(Tree(AHU|Alg|Equip)|pointnames|AHUinfo|global|ImpactDays|Annualize|HistoryConsole(_NEW)?).csv/)) {	#NOTE: must add files here to be rejected
		next;
	}	#the above throws away non-csv files #(commented out comment, lol)#or already converted files.
	$inputFile =~ m/(.*)\.csv/;
	open(my $sortedOutput, '>', $1."_sort.csv");
	print "sorting $inputFile:\n";
	
	our $timestampColName = "TT";
	
	
	our %rawHash = csvToRawHash($inputFile, "constants");
	
	sub timeStampSort {
		my $first = galaxyTimestampToDateTime($a, $year);
		my $second = galaxyTimestampToDateTime($b, $year);
		return &timeCompare( $first, $second);
	}
	sub timeStampIndexSort {
		my $first = galaxyTimestampToDateTime($rawHash{"$timestampColName"}[$a], $year);
		my $second = galaxyTimestampToDateTime($rawHash{"$timestampColName"}[$b], $year);
		return &timeCompare( $first, $second);
	}
	
	my @sortedIndex = sort timeStampIndexSort 0..(scalar @{ $rawHash{"$timestampColName"} } - 1);
	
	foreach my $column (keys %rawHash) {	#sorts everything based upon $timestampColName sorting
		@{$rawHash{$column}} = @{$rawHash{$column}}[@sortedIndex];   #here's the TimeIndex thing
	}
	
	foreach my $key ( 	#prints Header
			sort { #puts $timestampColName first...
				if ($a eq $timestampColName) { return -1; }
				elsif ($b eq $timestampColName) { return 1; }
				else { return $a cmp $b; } 
			} (keys %rawHash) 
		) {
			print $sortedOutput $key.",";
		}
	print $sortedOutput "\n";
	for (my $i = 0; $i < (scalar @{ $rawHash{"$timestampColName"} }); $i++)
	{
		foreach my $key ( 
			sort { #puts $timestampColName first...
				if ($a eq $timestampColName) { return -1; }
				elsif ($b eq $timestampColName) { return 1; }
				else { return $a cmp $b; } 
			} (keys %rawHash) 
		) {
			print $sortedOutput $rawHash{$key}[$i].",";
		}
	print ".";
	print $sortedOutput "\n";
	}
	print "\n";
	
	undef %rawHash;
	undef @sortedIndex;
}
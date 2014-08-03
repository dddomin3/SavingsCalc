#!/usr/bin/perl

#TODO: Refactor: Throw all AHUinfo.csv into the AHU object. MAKE THE AHU OBJECT EAT THE ENTIRE CODE
#TODO: Refactor: Throw all the point info (including global!) into the AHU object. MAKE THE AHU OBJECT EAT THE ENTIRE CODE

open(my $dbg, '>', 'dbg.txt') or die "Could not open file";	#for dumpers since DateTime is fucking annoying, goddamn
open(my $ft, '>', 'HistoryConsole_save.pl');
open(my $ooo, '>', 'outofocc_save.pl');
print $ooo "Timestamp,CalcSFS,SFS,SCH,HP,kWHP,CalcVFD,SupVFD,elecsave,active\n";

use warnings "all";
use strict;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);
use DateTime;
use AHU;
use diagnostics -verbose;

use Time::HiRes qw(usleep);

#constants
my $Konst = 8.1003223*(10**-5); #kW/F*CFM
my $kWHP = .746; #kWh/HP
my $Kenth = 9.34591*10**(-8);
my $Kdrybulb = 2.25009*10**(-8);

my $excel = 0;	#flag letting program know it was saved in excel. Excel deletes the comma at the end of a line in a csv file, while i assumed it was here.

#specifically for outputs (TreeMapData, ReportData)
###TreeMapData###
my %equip =	(
			"Air Handler (All)" => {
										"Tickets" => 0,
										"Value" => 0
									},
			"Other Equipment" => {
										"Tickets" => 0,
										"Value" => 0
									},						

);

my %monthlyTicketCounts;

my %ahuhash;
my %alg;
my $ticketcount = 0; #count total number of tickets running through code.
my $AnnSum = 0; #temp holder used to sum up annualized savings for specific categories
my $AnnSumo = 0; #sum up all annualized savings ever, forever ultimate team go!
my $AnnkWh = 0; #sum up all kWh (Do this BEFORE conversion to type!)
my $Anngas = 0; my $Annsteam = 0; #sum up all gas and steam
my $newAnom; #create an anomaly ticket is an old FDD analytic, or keep anomaly the same if anomaly exists.
my $cmc = 0; my $cmcsave = 0; #current month closed
my $cmo = 0; my $cmosave = 0; #current month still open
my $pmc = 0; my $pmcsave = 0; #previous (carryover) month closed
my $pmo = 0; my $pmosave = 0; #previous (carryover) month still open
my $lifec = 0; my $lifecsave = 0; #lifetime completed
my $lifeo = 0; my $lifeosave = 0; #lifetime open
my $ticketsum = 0; #sum up ALL tickets!
my %mhash; my $cdate;

my %latestAnnul; #Dennis' addition.

my $Calg; my $Oalg;

my %hashalg; my $algalg; my $AnnSumi = 0;

my %stdname;
my $bobmarley;

# $stdname{"Site"}{"Unit"}{"name"} = "stdname"
# hash, that stores hashes, that stores hashes, that has the standard point names...
my @globalcolkey;
my $ticket;
my %AHUinfo;
my %annualize;
#hash that stores AHUinfo.csv file
our %global;
#hash that stores global values, such as OAT, etc

my %savingstot;
my @savingskey = qw(OutofOccT DATDevH DATDevC DSPDevT SimHCT LeakyVlvT LeakyDampT StuckDampT EconMalfT OutofOccH OutofOccC OutofOccF DATDevT DSPDevF SimHCH SimHCC LeakyVlvH LeakyVlvC LeakyDampH LeakyDampC StuckDampH StuckDampC EconMalfH EconMalfC);
#hashes store savings data. %savings is per AHU, per analytic, per timestamp, %savingstot is total per analytic per AHU
#$savingstot{$Site}{$AHU}{Analytic}

#{INPUTS
print "\n\t\t    +----------------------------------------+\n";
print   "\t\t    |   Welcome to the Savings Calculator!   |\n";
print   "\t\t    +----------------------------------------+\n\n";
print "Before we begin, Could I have the site you are currently calculating for? This is used to look for past data, so make sure you give me the correct site! (e.g. GLOB, SWIC):\n";
my $sitename = <STDIN>;
chomp ($sitename);
print "May I also have the year that your data begins on? If this is incorrect, your tickets will not match up:\n";
my $datayear = <STDIN>;
chomp $datayear;
my $globalyear = $datayear;
print "Does your site observe DST?(Y/N) Case sensitive.\n";
my $dst = <STDIN>;
chomp $dst;
if ($dst =~ m/Y/)
{
	$dst = 'America/New_York'; print "Observing DST\n";
}
else 
{
	$dst = 'UTC';
	print "Not observing DST\n";
}

print "Does your site use STANDARD AMERICAN UNITS? (Y/N) Case sensitive.\n";
my $SIBrit = <STDIN>;
if ($SIBrit =~ m/Y/)
{
	#print "British Units are the best, Ol' Chap!\n";
	print "THIS IS AMERICA!!!!!!!!!!!!!!!!!!!!!!!!!\n";
}
else 
{
	print "Good. SI is more logical anyways.\n";
	$Konst = 0.3089; #(kWh/((m3/s)*degC))
	$kWHP = 1; #kWh to kwh cuz fuck HP
	#$Kenth = 9.34591*10**(-8);
	#$Kdrybulb = 2.25009*10**(-8);
}
	
print "Could you now enter the month this report is being made for? (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\n";
my $cmonth = <STDIN>;
chomp $cmonth;
print "Now, what is the year for the reporting month?\n";
my $cyear = <STDIN>;
chomp $cyear;
print "\nThank you! Please hold while your call is being transferred\n";
#find the numeric value for the current month!
my $currentmonth = 0;
my @monthnames = qw (Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec OMFGWTFBBQ);
for ( my $poo = 0; $poo < scalar (@monthnames); $poo++ )
{
	if( $monthnames[$poo] eq $cmonth )
	{
		$currentmonth = $poo+1;
		last;
	}
	if( $poo == 12 ){ die "Invalid month name\n"; }
}
if ($currentmonth <= 9)
{
	$cdate = "$cyear-0$currentmonth"; #set the current date to the format YYYY-MM to know what the most recent month is.
}
if ($currentmonth >=10)
{
	$cdate = "$cyear-$currentmonth"; #if it is Oct/Nov/Dec
}
	
#} INPUTS
opendir DIR, "." or die $!; 	#grabs all files in directory
open(DIAG, ">", "DIAG.txt") or die $!;

sub timeIndex
#Input: 2 DateTime Timestamps: TicketTime, DataTime
#Output: The amount of 15 minute timestamps between $ticket - $data, signed according to that math.
#makes sure to account for daylight savings, and ignores leap seconds.
{
	my $ticket = $_[0]->clone->set_time_zone('UTC')->set_time_zone('floating');
	my $data = $_[1]->clone->set_time_zone('UTC')->set_time_zone('floating');

	return ( $ticket->subtract_datetime_absolute($data)->in_units("seconds") / 900 );
}

sub Parsehead
#parses header of data. takes in header string. Outputs @colkey, which is an array of the column order.
{
	my @colkey;	#array that holds the order of the columns. helps A LOT with parsing and printing from these files
	my $head = $_[0];
	my $AHUname = $_[1];
	my $colnum = 0;
	$colkey[0] = "TT";	
	while ($head =~ s/,(.*?),/,/)	#matches one full column name #TODO: Instead of substitution, it might be cleaner with just m//g (global matching)
	{
		$colnum++;	#first column is always timestamp. Don't wanna do any crazy calcs with it...
		my $columntitle = $1; 	#stores column name in variable
		$columntitle =~ s/\"//g; #removes all quotes
		$columntitle =~ m/(.*?)-(.*?)-(.*?)/;
		my $point = $1;
		my $actpoint;
		
		if(exists ($stdname{$sitename}))	#site
		{
			if (exists ( $stdname{$sitename}{$AHUname} ))	#Unit
			{
				if (exists ( $stdname{$sitename}{$AHUname}{$point})) #Unit exist. If the point exists, just overwrite data..
				{
					$actpoint = $stdname{$sitename}{$AHUname}{$point};
					$colkey[$colnum] = $actpoint;	#add point to column key.
					next;
				}
			}
		}
		

		print "\nHey. I found \"$point\". What is this?\n(Please use standard PCI naming where applicable.)\n\tPut NULL (w/o quotes) if the value is useless.\n";
		$actpoint = <STDIN>;
		chomp($actpoint);
		$stdname{$sitename}{$AHUname}{$point} = $actpoint;
		$colkey[$colnum] = $actpoint;	#add point to column key.
	}
	return @colkey;
}
print ".\n";
sub Timeround	#rounds given TimeDate to the nearest 15 using conventional rounding rules.
#INPUT: TimeDate
#output: Rounded TimeDate
{
	my $tt = $_[0]->clone;

	#rounding boundaries
	my $SA = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 0,
				second => 0,
				);
	my $AB = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 7,
				second => 30,
				);
	my $BC = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 22,
				second => 30,
				);
	my $CD = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 37,
				second => 30,
				);
	my $DE = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 52,
				second => 30,
				);
	my $EE = DateTime->new(year => $tt->year, month => $tt->month, hour => $tt->hour, day => $tt->day,
				minute => 59,
				second => 59,
				);
				

	if (($SA <= $tt) && ($tt < $AB))
	{
		$tt->set_minute(0);
		$tt->set_second(0);
		
		return $tt;
	}
	elsif (($AB <= $tt) && ($tt < $BC))
	{
		$tt->set_minute(15);
		$tt->set_second(0);
		
		return $tt;
	}
	elsif (($BC <= $tt) && ($tt < $CD))
	{
		$tt->set_minute(30);
		$tt->set_second(0);

		return $tt;
	}
	elsif (($CD <= $tt) && ($tt < $DE))
	{
		$tt->set_minute(45);
		$tt->set_second(0);

		return $tt;
	}
	elsif (($DE <= $tt) && ($tt <= $EE))
	{
		$tt->add(hours => 1);
		$tt->set_minute(0);
		$tt->set_second(0);

		return $tt;
	}
}
print ".\n";
if (-e "ImpactDays.csv")	#gets all the annualization constants, and shoves them into %annualize
{
	my $num=0;
	my @info;
	my @keys;
	my @values;
	my $counter;
	my $tempfac;

	open(my $filehandle, '<', 'ImpactDays.csv') or die "Could not open file";
	while (<$filehandle>)
	{
		$num++;
		my $line = $_;
		@info = split(',', $line);
		my $start = shift(@info);
		my $len = scalar(@info);
		$counter = $len - 1;
	
		if ($num == 1)
		{
			for (my $x = 0; $x <= $counter; $x++)
			{
				chomp ($info[$x]);
				$keys[$x] = $info[$x];
			}
		}
		elsif ($num == 3)
		{
			for (my $x=0; $x <= $counter; $x++)
			{
				chomp ($info[$x]);
				$values[$x] = $info[$x];
			}
			$tempfac = $start;
		}
	}

	my %inventory;

	for (my $y=0; $y <= $counter; $y++)
	{
		$inventory{$keys[$y]}=$values[$y];
	}
	
	my $fac = $tempfac;
	$annualize{$fac} = \%inventory;
	
}
else {die "You forgot ImpactDays.csv";}
print ".\n";
if (-e "HistoryConsole.csv")
{
	my $num=0;
	my @info;
	my $line;
	my $counter;
	my @header;
	my $a;
	my $b;
	my $c;
	my $d;
	my $e;
	my $f;
	my $g;
	my $h;
	my $i;
	my $j;
	my $k;
	my $l;
	my $brady;
	my $pats;
	my $sox;
	my %rutgers;
	my %marching;	
	my %scarlet;
	my %knights;
	my @thing;
	my @spell;
	my $timestr1;
	my $timestr2;
	my $pedroia;
	my $bigpapi;
	my $sanu;
	my $gronk;
	my $faulk;
	my $nova;
	my $clot;
	my $href;
	

	open(my $fh, '<', 'HistoryConsole.csv') or die "Could not open file";
	open(my $ff, '>', 'HistoryConsole_NEW.csv');
	while (<$fh>)
	{
		$num++;
		my $line = $_; #one row at a time
		
		for (my $y=0; $y<=2; $y++) #for loop to find, store, and replace any parameters enclosed in " ". for created/open time there is a comma present, this will prevent split from making issues.
		{
			$line =~ s/(".*?")/LOL/;
			$thing[$y] = $1;
		}
		
		@info = split(',', $line);
		my $len = scalar(@info);
		$counter = $len - 1;
		
		if ($num == 1) #First row to discover column number for each "Type" (Facility, Asset, Anomaly, etc...)
		{
			for (my $x=0; $x <= $counter; $x++) #for the length of the 1st row, match the given "parameter name" and spit out the corresponding column number (where column "A" = 1, "B" = 2...
			{
				if($info[$x] =~ m/Event ID/ || $info[$x] =~ m/TicketID/ || $info[$x] =~ m/Ticket ID/ || $info[$x] =~ m/TicketId/)
				{
					$a=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Facility/)
				{
					$b=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Asset/)
				{
					$c=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Created Time/ || $info[$x] =~ m/CreatedTime/) #### $d
				{
					$d=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/SetClosedTime/ || $info[$x] =~ m/Set Closed Time/ || $info[$x] =~ m/SetClosed Time/ || $info[$x] =~ m/ClosedTime/ || $info[$x] =~ m/Closed Time/) #### $e
				{
					$e=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Anomaly/)
				{
					$f=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/^Status/)
				{
					$g=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Cause/)
				{
					$h=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Effect/)
				{
					$i=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Source/)
				{
					$j=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~  m/ReturnStatus/ || $info[$x] =~ m/Return Status/)
				{
					$k=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
				if($info[$x] =~ m/Comments/) #### $l
				{
					$l=$x;
					chomp ($info[$x]);
					push @header, $x;
				}
			}
			foreach my $dennis (@header)
			{
				print $ff $info[$dennis].",";
			}
			print $ff "\n";
			

		}
		if ( $num>1 && ($info[$a] ne "") && ($info[$a] ne "Event ID") && ($info[$a] ne "TicketID") && ($info[$a] ne "Ticket ID") && ($info[$a] ne "TicketId")) #if the column does NOT say "Event ID" and is NOT blank (""), then the row should be a legit Ticket && ($info[$a] ne "") && ($info[$a] ne "Event ID")
		{
		
			######Time/Date formatting Section, does not round time, but converts it into the standard: "YYYY-MM-DDT00:00:00" format######
		
			#####START TIME#####
			
			$thing[0] =~ m/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+0?([0-3]?[0-9]),\s+0*?(\d*)\s+0*?([0-3]?[0-9]):([0-5]?[0-9]):([0-5]?[0-9])/;
			my $month = 0;
			
			my @monthnames = qw (Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec OMFGWTFBBQ);
			for ( my $poo = 0; $poo < scalar (@monthnames); $poo++ )
			{
				if( $monthnames[$poo] eq $1 )
				{
					$month = $poo+1;
					last;
				}
				if( $poo == 12 ){ die "Invalid month name\n"; }
			}

			my $ya = DateTime->new
			( 
				year => $3, month => $month, day => $2,
				hour => $4,	minute => $5, second => $6,	time_zone => $dst,
			);
							
			$pats = $ya;
				
			###########ENDTIME, put in standard format######
			#If there is no closed time (ticket still open)#
			if (($info[$e] eq "") || ($info[$e] eq "N/A"))
			{
				$thing[2] = $thing[1];
				$sox = "NULL";
			}
			#if there is a closed time#
			else	#this can just be else, they are logically equiv
			{			
						
				# #						$1-month								  		$2-Day  	$3-Year			$4-hr		 $5-Min		  		$6-Sec
				$thing[1] =~ m/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+0?([0-3]?[0-9]),\s+0*?(\d*)\s+0*?([0-3]?[0-9]):([0-5]?[0-9]):([0-5]?[0-9])/;
				my $month = 0;
				my @monthnames = qw (Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec OMFGWTFBBQ);
				for ( my $poo = 0; $poo < scalar (@monthnames); $poo++ )
				{
					if( $monthnames[$poo] eq $1 )
					{
						$month = $poo+1;
						last;
					}
					if( $poo == 12 ){ die "Invalid month name\n"; }
				}

				my $ya = DateTime->new
				( 
					year => $3, month => $month, day => $2,
					hour => $4,	minute => $5, second => $6,	time_zone => $dst, 
				);
				$sox = $ya;
			}
			#####Print an organized version of the original file#####
			print $ff $info[$a];
			print $ff ",";
			print $ff $info[$b];
			print $ff ",";
			print $ff $info[$c];
			print $ff ",";
			print $ff $pats;
			print $ff ",";
			print $ff $sox;
			print $ff ",";
			###if Anomaly is blank or N/A, insert null. Else if don't change###
			if (($info[$f] eq "") || ($info[$f] eq "N/A"))
			{
				$bigpapi = "NULL"
			}
			else
			{
				$bigpapi = $info[$f];
			}
			print $ff $bigpapi;
			print $ff ",";
			print $ff $info[$g];
			print $ff ",";
			###if Cause is blank or N/A, insert null. Else if don't change###

			if (($info[$h] eq "") || ($info[$h] eq "N/A"))
			{
				$sanu = "NULL";
			}
			else
			{
				$sanu = $info[$h];
			}
			print $ff $sanu;
			print $ff ",";
			###if Effect is blank or N/A, insert NULL. Else if don't change###
			
			if (($info[$i] eq "") || ($info[$i] eq "N/A"))
			{
				$gronk = "NULL";
			}
			else
			{
				$gronk = $info[$i];
			}
			
			print $ff $gronk;
			
			print $ff ",";
			print $ff $info[$j];
			print $ff ",";
			print $ff $info[$k];
			print $ff ",";
			
			#This is for the comment column#
			
			if ($info[$l] eq "LOL\n") #for comments if it was replaced
			{
				print $ff $thing[2];
				$brady = join(',',$thing[2]);
				print $ff "\n";
			}
			
			else #for comments if it was NOT replaced
			{
				print $ff ($info[$l]);
				$brady = join(',',$info[$l]);
			}	
					
			#####MAKE A HASH#####
			
			$pedroia = $info[$a]; #$pedroia will be event ID 
			$faulk = $info[$c]; #$faulk will be Asset name
			$nova = $info[$b]; #$nova will be the Facility name
			chomp($brady);
			$rutgers{$sitename}{$faulk}{$pedroia}= {"StartTime",$pats,"EndTime",$sox,"Anomaly","$bigpapi","Status",$info[$g],"Cause","$sanu","Effect","$gronk","Source",$info[$j],"Return Status",$info[$k],"Comments","$brady"};
		}
	}
	$ticket = \%rutgers;
	#print $ft Dumper \%rutgers; #same shit
	
	close $fh;
	close $ff;
} 
else {die "You forgot HistoryConsole.csv";}
print ".\n";
#populates %stdname with previously given translations
if (-e "pointnames.csv")  
{
	open(NAME, "<", "pointnames.csv") or die $!;
	#populate the best datastructure in the world
	my $line;
	while (<NAME>)
	{
		$line = $_; #this $_ is like an auto variable that grabs the <> variable
		if($line !~ m/,\n$/){ $line =~ s/\n$/,\n/; }
				#1Site  2Unit 3Point 4Stdname
		$line =~ m/(.*?),(.*?),(.*?),([^,]*)/;	#matches column
		if( ($1 eq "")||($2 eq "")||($3 eq "")||($4 eq "") )
		{
			die "\tIncorrect pointnames.csv format! 1:$1 2:$2 3:$3 4:$4\n";
		}
		my %temp;	#1st level temp hash to shove into other hash
		my %temptee; #2nd level temp hash
		#TODO: there's actually a really easy way to do this with the hash reference {} thing, but I was dumb when I did that.
		if(!exists ($stdname{$1}))	#site doesn't exists. Create all levels
		{
			$temptee{$3} = $4;
			$temp{$2} = \%temptee;
			$stdname{$1} = \%temp;
		}
		elsif (!exists ( $stdname{$1}{$2} ))	#site exists, but the Unit does not. create unit hash
		{
			$temptee{$3} = $4;
			$stdname{$1}{$2} = \%temptee;
		}
		elsif (!exists ( $stdname{$1}{$2}{$3} )) #Unit exist. If the point exists, just overwrite data..
		{
			$stdname{$1}{$2}{$3} = $4;
		}
	}
	close(NAME);
}
print ".\n";
if(-e "AHUinfo.csv")
{
	open(INFO, "<", "AHUinfo.csv") or die $!;
	my $line = <INFO>;
	my @infocol;
	$line =~ s/(.*?),(.*?),//;	#throws away facility and AHU titles because it is dealt with differently...
	if($line !~ m/,\n$/){$line =~ s/\n$/,\n/; $excel = 1;}	#if it was saved in excel, it erases the final comma. this reads it
	while ($line =~ s/(.*?),//)	#obtains column names and populates the info col array.
	{
		push (@infocol, $1);
	}

	#DEFAULT VALUES
	$line = <INFO>;
	if($excel&&($line =~ m/,\n$/)){$line =~ s/,\n$/,NULL,\n/; }	#if in excel mode, and line ends with comma, replace with ,NULL,. Comma at the end means the last value is blank
	elsif($excel&&($line !~ m/,\n$/)){$line =~ s/\n$/,\n/; }			#if in excel mode, and it doesn't end with a comma, add the comma
	$line =~ s/,,/,NULL,/g;					#replaces empty values with null
	$line =~ s/(.*?),(.*?),//;
	if( $1 eq "DEFAULT")
	{
		my $i = 0; #iterator for array
		my %h1; #hash one, counting from inside out. infoname => info

		while ($line =~ s/(.*?),//)	#obtains column names and populates the info col array.
		{
			if($1 eq "NULL")
			{
				print DIAG "FATAL ERROR: Default AHU info has blank values";
				die "FATAL ERROR: Default AHU info has blank values";
			}
			$h1{$infocol[$i++]} = $1;
		}
		#		$h2{$infoAHU} = \%h1;
		$AHUinfo{"DEFAULT"}{"DEFAULT"} = \%h1;
	}
	else
	{
		print DIAG "FATAL ERROR: Default AHU info is not the 2nd line of AHUinfo.csv";
		die "FATAL ERROR: Default AHU info is not the 2nd line of AHUinfo.csv";
	}
	
	while (<INFO>)
	{
		$line = $_;
		if($excel&&($line =~ m/,\n$/)){$line =~ s/,\n$/,NULL,\n/; }	#if in excel mode, and line ends with comma, replace with ,NULL,. Comma at the end means the last value is blank
		elsif($excel&&($line !~ m/,\n$/)){$line =~ s/\n$/,\n/; }			#if in excel mode, and it doesn't end with a comma, add the comma
		while ($line =~ s/,,/,NULL,/g){}					#replaces empty values with null
		$line =~ s/(.*?),(.*?),//;
		my $i = 0; #iterator for array
		my %h1; #hash one, counting from inside out. infoname => info
#		my %h2; #hash two, AHU => (infoname => info)
		if ($1 ne $sitename) {next;} #if facility doesn't match, skip line NOTE:One Facility
		my $infoSITE = $1;
		my $infoAHU = $2;
		while ($line =~ s/(.*?),//)	#obtains column names and populates the info col array.
		{
			if ($1 eq "NULL")
			{
				$h1{$infocol[$i]} = $AHUinfo{"DEFAULT"}{"DEFAULT"}{$infocol[$i]};
				print DIAG "$infoSITE\t$infoAHU\t$infocol[$i]\tMissing Value. Set to default. $AHUinfo{'DEFAULT'}{'DEFAULT'}{$infocol[$i]}\n";
			}
			else
			{
				$AHUinfo{$infoSITE}{$infoAHU}{$infocol[$i]} = $1;
			}
			$i++;
		}
		#print "\n";
#		$h2{$infoAHU} = \%h1;
	}
	$excel = 0;
}
else {die "You forgot AHUinfo.csv... Did you read the documentation?! C'mon.";}
print ".\n";
if(-e "global.csv")
{
	open (GLOBAL, "<", "global.csv") or die $!;
	my @colkey;	#array keep track of what point is in which column
	my $firstline = <GLOBAL>;
	my $colnum = 0;
	#$savings{$Site}{$AHU}{$Analytic}[$i]
#----------Header parsing-----------V
	if($firstline !~ m/,\n$/){$firstline =~ s/\n$/,\n/; $excel = 1;}	#if it was saved in excel, it erases the final comma. this readds it. Sets excel flag to true
	$firstline =~ m/,(.*?)-(.*?)-(.*?),/;

	@colkey = &Parsehead ($firstline, "global");	#parses header
	foreach (@colkey)
	{
		$global{$_} = [];
	}
	@globalcolkey = @colkey;
	my $firsttime = 1;	#figures out if its the first, or row of file.
	my $prevtime; #DateTime. Stores the value of the previous runs time stamp
#----------Header parsing-----------^
	while (<GLOBAL>)
{
#----------Data Treatment-----------V
		my $laziness = $_;
		if($excel&&($laziness =~ m/,\n$/)){$laziness =~ s/,\n$/,NULL,\n/;}	#if in excel mode, and line ends with comma, replace with ,NULL,. Just think about why that's needed -_-
		elsif($excel&&($laziness !~ m/,\n$/)){$laziness =~ s/\n$/,\n/;}			#if in excel mode, and it doesn't end with a comma, add the comma

		$laziness =~ s/  \( OK \)//g; #removes all OKs$laziness =~ s/  \( OK \)//g; #removes all OKs
		$laziness =~ s/  \( Overwritten \)//g; #removes all Overwrittens
#		$laziness =~ s/(  \( OK \)|\")//g; #removes all OKs AND QUOTES
#		$laziness =~ s/\"//g; #removes all quotes
		while ($laziness =~ s/,,/,NULL,/g){}; #replace empty values with NULL for future treatment
		if($laziness =~ m/\(/)	#If there is another parenthesis, replace data with NULL.
		{
			$laziness =~ s/[^,]*?\(.*?\),/NULL,/g;
		} 
		#print CONV $laziness; #if nothing wrong with line, add it to converted file.
#----------Hash Population----------V
		
		$colnum = 0;
		my $back = 0;	#flag to see if it needs to fill in the previous time stamp
		
		while ($laziness =~ s/(.*?),//)	#matches  column value
		{
			if ($colnum == 0)		#timestamp treatment code TT is time stamp
			{
				$back = 0;	#this clears the flag letting data adders know to add to last timestamp.
				my $timestr = $1;
				#											    			$1-month								       $2-DOM			$3-hr		 $4-Min		  	$5-Sec
				$timestr =~ m/(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+0*?([0-3]?[0-9])\s+([0-2]?[0-9]):([0-5]?[0-9]):0*?([0-5]?[0-9])/;
				my $month = 0;
				my @monthnames = qw (Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec OMFGWTFBBQ);
				for ( my $poo = 0; $poo < scalar (@monthnames); $poo++ )
				{
					if( $monthnames[$poo] eq $1 )
					{
						$month = $poo+1;
						last;
					}
					if( $poo == 12 ){ die "Invalid month name\n"; }
				}
				
				
				my $tt = DateTime->new( year => $globalyear, #galaxy time stamps don't have a friggin year, go figure!
				month => $month, day => $2,
				hour => $3,	minute => $4, second => $5,
				time_zone => $dst, 
				);
				
				if( $tt->year != &Timeround($tt)->year)
				{
					$globalyear++;
				}
				$tt = &Timeround($tt);
				if ($firsttime) 	#if first run, make it so it doesn't do any crazy timestamp things.
				{
					$prevtime = DateTime->new( year => $globalyear , #galaxy time stamps don't have a friggin year, go figure!
												month => 1, day => 1,
												hour => 0,	minute => 0, second => 0,
												time_zone => $dst, 
												);
					push @{$global{"TT"}}, $prevtime;
					for (my $colprints = 1; $colprints < scalar @colkey; $colprints++)
					{
						push @{$global{$colkey[$colprints]}}, "NULL";	#sets all other data to NULL (since it doesn't exist)
					}
					$firsttime = 0;
				}
				else	#prevtime is just the last added timestamp
				{
					$prevtime = $global{"TT"}[-1]->clone;
				}
				

				if ( timeIndex($tt, $prevtime) == 0)	#does not need to add a new timestamp, but needs set flag so data gets placed into previous timestamp
				{
					$back = 1;	#flag to let datadders know to add to last timestamp, not to push.
					$colnum++;	#this make its go to the next column.
				}
				elsif ( timeIndex($tt, $prevtime) == 1)		#its the next timestamp. Just add it.
				{
					push @{$global{"TT"}}, $tt;
					$colnum++;
				}
				else	#this should be anything where the difference is negative (so it needs to jump a year) or the differnece is more than 1 timestamp, so it needs to add timestamps.
				{
					while ((timeIndex($tt, $prevtime) < 0)||(timeIndex($tt, $prevtime) > 1))
					{
						$prevtime = $prevtime->clone->add( minutes => 15 ); #at this point, e.g. your $prevtime == 0:00, and your $tt is 1:00. add 15 minutes to $prevtime
						if($prevtime->year() != $globalyear)	#if adding 15 minutes causes your $prevtime to jump a year
						{ 
							print timeIndex($tt, $prevtime)."\n".$prevtime."\n".$tt."\n"; 
							$globalyear = $prevtime->year(); 			#change the datayear to the new year to reflect this. 
							$tt->set_year($globalyear); 				#since you haven't hit the escape condition, $tt HAS to be next year (assuming data is ordered correcttly)
							print timeIndex($tt, $prevtime)."\n".$prevtime."\n".$tt."\n";
							if(timeIndex($tt, $prevtime) == 0) {last;}
						}
						push @{$global{"TT"}}, $prevtime;
						for (my $colprints = 1; $colprints < scalar @colkey; $colprints++)
						{
							push @{$global{$colkey[$colprints]}}, "NULL";	#sets all other data to NULL (since it doesn't exist)
						}
					}
					push @{$global{"TT"}}, $tt;	#finally, when the difference in timestamps is gucci, add $tt, and continue to data adders
					$colnum++;
				}
			}
			elsif ($1 eq "0.00")	#data adder. sometimes this is taken as a string and not a number
			{
				if ( $back )
				{
					if ( $global{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$global{$colkey[$colnum]}[-1] = 0;
					}
					$colnum++;
				}
				else
				{
					push @{$global{$colkey[$colnum]}}, 0; 
					$colnum++;
				}
			}
			elsif ($1 eq "1.00")	#data adder. sometimes this is taken as a string and not a number
			{
				if ( $back )
				{
					if ( $global{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$global{$colkey[$colnum]}[-1] = 1;
					}
					$colnum++;
				}
				else
				{
					push @{$global{$colkey[$colnum]}}, 1; 
					$colnum++;
				}
			}
			else	#data adder
			{
				if ( $back )
				{
					if ( $global{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$global{$colkey[$colnum]}[-1] = $1;
					}
					$colnum++;
				}
				else
				{
					push @{$global{$colkey[$colnum]}}, $1; 
					$colnum++;
				}
			}
		}
#----------Hash Population----------^

#----------Data Treatment-----------^
	}
}
else {print "No, or misnamed global.csv!"; print DIAG "No, or misnamed global.csv!";}
print ".\n";
#goes through all files in current directory
while (my $inputfile = readdir(DIR))
{
	if(!($inputfile =~ m/\.csv/)||($inputfile =~ m/_save\.csv/)||($inputfile =~ m/(Tree(AHU|Alg|Equip)|pointnames|AHUinfo|global|ImpactDays|Annualize|HistoryConsole(_NEW)?).csv/))	#NOTE: must add files here to be rejected
	{
		next;
	}	#the above throws away non-csv files or already converted files.

	print "\n\tProcessing $inputfile \n";
	my $outputfile = $inputfile;
	$outputfile =~ s/\.csv/_save\.csv/;
		#renames output file name to inFILE.csv to inFILE_save.csv

	open(my $inz, "<", $inputfile) or die $!;
	open(CONV, ">", $outputfile) or die $!;
	
	our %AHU;	#makes the AHU hash global. Needs to be here, since redefinition of it deletes the old AHU hash it its entirety
	our $AHUmap = AHU->new();
	my @colkey;	#array keep track of what point is in which column
	my $firstline = <$inz>;
	my $colnum = 0;
	our $AHUname = "";	#global AHU name
	my %savings;
	#$savings{$Site}{$AHU}{$Analytic}[$i]
#----------Header parsing-----------V
	if($firstline !~ m/,\n$/){$firstline =~ s/\n$/,\n/; $excel = 1;}	#if it was saved in excel, it erases the final comma. this readds it. Sets excel flag to true
	$firstline =~ m/,(.*?)-(.*?)-(.*?),/;
	$AHUname = $2;
	print DIAG "Using AHUname: $AHUname for Filename: $inputfile\n";
	print "Using AHUname: $AHUname for Filename: $inputfile\n";

	@colkey = &Parsehead ($firstline, $AHUname);	#parses header
	
	foreach my $analytic (@savingskey) { $savings{$sitename}{$AHUname}{$analytic} = []; $savingstot{$sitename}{$AHUname}{$analytic} = 0;  } #initializes all savings values to zero. Grabs what the values are from @savingskey
	
	foreach (@colkey)
	{
		$AHU{$_} = [];
		if($_ ne "NULL") { print CONV "$_,"; }
	}
	foreach (@globalcolkey)
	{
		print CONV "$_,";
	}
	print CONV "\n";
	my $firsttime = 1;	#figures out if its the first, or row of file.
	my $prevtime; #DateTime. Stores the value of the previous runs time stamp
	my $thisyear = $datayear; #so each AHU has it's own year "bubble". otherwise, if this AHU needs a year increment, it'll increment the next AHUs starting year, lol.
#----------Header parsing-----------^
	while (<$inz>)
	{
#----------Data Treatment-----------V
		my $laziness = $_;
		if($excel&&($laziness =~ m/,\n$/)){$laziness =~ s/,\n$/,NULL,\n/;}	#if in excel mode, and line ends with comma, replace with ,NULL,. Just think about why that's needed -_-
		elsif($excel&&($laziness !~ m/,\n$/)){$laziness =~ s/\n$/,\n/;}			#if in excel mode, and it doesn't end with a comma, add the comma

		$laziness =~ s/  \( OK \)//g; #removes all OKs
		$laziness =~ s/  \( Overridden \)//g; #removes all Overriddens
		$laziness =~ s/  \( Filler Data \)//g; #removes all Filler Datas
#		$laziness =~ s/(  \( OK \)|\")//g; #removes all OKs AND QUOTES
#		$laziness =~ s/\"//g; #removes all quotes
		while ($laziness =~ s/,,/,NULL,/g){}; #replace empty values with NULL for future treatment
		if($laziness =~ m/\(/)	#If there is another parenthesis, replace data with NULL.
		{
			$laziness =~ s/[^,]*?\(.*?\),/NULL,/g; 
		} 
		#print CONV $laziness; #if nothing wrong with line, add it to converted file.
#----------Hash Population----------V
		
		$colnum = 0;
		my $back = 0;	#flag to see if it needs to fill in the previous time stamp
		while ($laziness =~ s/(.*?),//)	#matches  column value
		{
			if ($colnum == 0)		#timestamp treatment code TT is time stamp
			{
				$back = 0;	#this clears the flag letting data adders know to add to last timestamp.
				my $timestr = $1;
				#											    			$1-month								       $2-DOM			$3-hr		 $4-Min		  	$5-Sec
				$timestr =~ m/(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+0*?([0-3]?[0-9])\s+([0-2]?[0-9]):([0-5]?[0-9]):0*?([0-5]?[0-9])/;
				my $month = 0;
				my @monthnames = qw (Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec OMFGWTFBBQ);
				for ( my $poo = 0; $poo < scalar (@monthnames); $poo++ )
				{
					if( $monthnames[$poo] eq $1 )
					{
						$month = $poo+1;
						last;
					}
					if( $poo == 12 ){ die "Invalid month name\n"; }
				}
				
				
				my $tt = DateTime->new( year => $thisyear, #galaxy time stamps don't have a friggin year, go figure!
				month => $month, day => $2,
				hour => $3,	minute => $4, second => $5,
				time_zone => $dst, 
				);
				
				if( $tt->year != &Timeround($tt)->year)
				{
					$thisyear++;
				}
				$tt = &Timeround($tt);
				if ($firsttime) 	#if first run, make it so it doesn't do any crazy timestamp things.
				{
					$prevtime = DateTime->new( year => $thisyear , #galaxy time stamps don't have a friggin year, go figure!
												month => 1, day => 1,
												hour => 0,	minute => 0, second => 0,
												time_zone => $dst, 
												);
					push @{$AHU{"TT"}}, $prevtime;
					for (my $colprints = 1; $colprints < scalar @colkey; $colprints++)
					{
						push @{$AHU{$colkey[$colprints]}}, "NULL";	#sets all other data to NULL (since it doesn't exist)
					}
					$firsttime = 0;
				}
				else	#prevtime is just the last added timestamp
				{
					$prevtime = $AHU{"TT"}[-1]->clone;
				}
				

				if ( timeIndex($tt, $prevtime) == 0)	#does not need to add a new timestamp, but needs set flag so data gets placed into previous timestamp
				{
					$back = 1;	#flag to let datadders know to add to last timestamp, not to push.
					$colnum++;	#this make its go to the next column.
				}
				elsif ( timeIndex($tt, $prevtime) == 1)		#its the next timestamp. Just add it.
				{
					push @{$AHU{"TT"}}, $tt;
					$colnum++;
				}
				else	#this should be anything where the difference is negative (so it needs to jump a year) or the differnece is more than 1 timestamp, so it needs to add timestamps.
				{
					while ((timeIndex($tt, $prevtime) < 0)||(timeIndex($tt, $prevtime) > 1))
					{
						$prevtime = $prevtime->clone->add( minutes => 15 ); #at this point, e.g. your $prevtime == 0:00, and your $tt is 1:00. add 15 minutes to $prevtime
						if($prevtime->year() != $thisyear)	#if adding 15 minutes causes your $prevtime to jump a year
						{ 
							print timeIndex($tt, $prevtime)."\n".$prevtime."\n".$tt."\n"; 
							$thisyear = $prevtime->year(); 			#change the datayear to the new year to reflect this. 
							$tt->set_year($thisyear); 				#since you haven't hit the escape condition, $tt HAS to be next year (assuming data is ordered correcttly)
							print timeIndex($tt, $prevtime)."\n".$prevtime."\n".$tt."\n";
							if(timeIndex($tt, $prevtime) == 0) {last;}
						}
						push @{$AHU{"TT"}}, $prevtime;
						for (my $colprints = 1; $colprints < scalar @colkey; $colprints++)
						{
							push @{$AHU{$colkey[$colprints]}}, "NULL";	#sets all other data to NULL (since it doesn't exist)
						}
					}
					push @{$AHU{"TT"}}, $tt;	#finally, when the difference in timestamps is gucci, add $tt, and continue to data adders
					$colnum++;
				}
			}
			elsif ($1 eq "0.00")
			{
				if ( $back )
				{
					if ( $AHU{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$AHU{$colkey[$colnum]}[-1] = 0;
					}
					$colnum++;
				}
				else
				{
					push @{$AHU{$colkey[$colnum]}}, 0; 
					$colnum++;
				}
			}
			elsif ($1 eq "1.00")
			{
				if ( $back )
				{
					if ( $AHU{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$AHU{$colkey[$colnum]}[-1] = 1;
					}
					$colnum++;
				}
				else
				{
					push @{$AHU{$colkey[$colnum]}}, 1; 
					$colnum++;
				}
			}
			else
			{
				if ( $back )
				{
					if ( $AHU{$colkey[$colnum]}[-1] eq "NULL" )
					{
						$AHU{$colkey[$colnum]}[-1] = $1;
					}
					$colnum++;
				}
				else
				{
					push @{$AHU{$colkey[$colnum]}}, $1; 
					$colnum++;
				}
			}
		}
#----------Hash Population----------^

#----------Data Treatment-----------^
	}
	#print Dumper \%AHU;

	#VVV conjunction-junction what's your FUNCTION VVV
	
	sub SetPlainArray	#Checks if input's key exists. If it does, returns the array in the AHU hash. Otherwise, returns an undefined array
	#INPUT: hash key for AHU array
	{
		my $key = $_[0];
		if ( exists $AHU{$key} ) { return @ {$AHU{$key} }; }
		elsif ( exists $global{$key} ) { return @ {$global{$key} }; }
		elsif ($key ne "N/A")	{print DIAG "\tNO DATA\t$key\n"; return;}
		else {return;}
	}

	sub FanOn
	#Tells you if the fan is on or not for several fans
	#use this: FanOn($i)
	{
		my $i = $_[0];

		my $FanOff = 0; #its 1 when a fan is off

		foreach my $SF ($AHUmap->getSF) #if a fan is on than $FanOn is 1
		{	
			if ( looks_like_number($AHU{$SF}[$i]))
			{
				if ($AHU{$SF}[$i]) { return 1;	}
				unless ($AHU{$SF}[$i]) { $FanOff = 1; }
			}
		}
		if ($FanOff) { return 0; }
		else { return "NULL";}
	}	

	sub PerFudge 
	#this converts any value to percent based on the provided Max and Min signal values
	#copy this and fill in correct point names: PerFudge(min position, max position, signal position)
	#who doesn't like fudge?
	#IMPORTANT: This MUST go above REALLYMakeVFD!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	{
		my $min = $_[0];
		my $max = $_[1];
		my $signal = $_[2];
		
		if (looks_like_number($min)&&looks_like_number($max)&&looks_like_number($signal))
		{return (100/($max-$min))*($signal-$min);}
		else{return "NULL";}
	}

	sub REALLYMakeVFD
	#IMPORTANT: PerFudge AND FanOn MUST go above this!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	#gets the most accurate VFD signal
	#use this: REALLYMakeVFD($i, $MaxCFM)
	{
		my $i = $_[0];
		my $CFMMax = $_[1];
		my $VFDcount = 0;
		my $CalSupVFD = 0;
		
		foreach my $SupVFD ($AHUmap->getSupVFD)
		{
			if (looks_like_number($AHU{$SupVFD}[$i]))
			{
				$VFDcount++;
				$CalSupVFD += PerFudge($AHUmap->getvfdmin($SupVFD),($AHUmap->getvfdmax($SupVFD)),$AHU{$SupVFD}[$i]);
			}
			else {return "NULL";}
		}
		
		if ($VFDcount == 0)
		{
			if(   looks_like_number($CFMMax) && looks_like_number(&FanOn($i)) && FanOn($i) && ((exists $AHU{"SupCFM"})||(exists $AHU{"CFM"})) && (looks_like_number($AHU{"SupCFM"}[$i])||looks_like_number($AHU{"CFM"}[$i]))  )
			{
				if ( (exists $AHU{"SupCFM"})&& looks_like_number($AHU{"SupCFM"}[$i]) )
				{
					if($AHU{"SupCFM"}[$i]>$CFMMax) {return 100;}
					elsif ( $AHU{"SupCFM"}[$i] < 0) {return 0;}
					else {return 100*($AHU{"SupCFM"}[$i]/$CFMMax);}
				}
				elsif ( (exists $AHU{"CFM"}) && looks_like_number($AHU{"CFM"}[$i]))
				{
					if ($AHU{"CFM"}[$i]>$CFMMax) {return 100;}
					elsif ( $AHU{"CFM"}[$i] < 0) {return 0;}
					else {return 100*($AHU{"CFM"}[$i]/$CFMMax);}
				}
			}
			elsif( looks_like_number(&FanOn($i)) ) 
			{
				return &FanOn($i)*100;
			}
			else {return "NULL";}
		}
		else {return $CalSupVFD/$VFDcount}
	}

	sub MakeVFD #Figures out what VFD is per timestamp. returns 1000 if CFM exists
	#Use this MakeVFD($i,$REALMakeVFD($i))
	{
		my $i = $_[0];
		my $REALSupVFD = $_[1];
		if( exists $AHU{"SupCFM"} ) { return 1000; }
		elsif( exists $AHU{"CFM"} ) { return 1010; }
		else { return $REALSupVFD; } #if there's a VFD point
	}
	
	sub MakeVFDDSP #RESETS THE ...woops caps lock...resets the VFD to normal so that DSP and Out of Occ calculate correctly 
	#INPUT: array index
	{
		my $i = $_[0];
		if( exists $AHU{"SupVFD"} ) { return $AHU{"SupVFD"}[$i]; } #if there's a VFD point
		elsif( exists $AHU{"SFS"} )
		{
			if(looks_like_number($AHU{"SFS"}[$i]))	{ return $AHU{"SFS"}[$i]*100; }
			else { return "NULL"; }
		}
		else {return "NULL";}
	}
	sub MakeCFM
	#figures out the current CFM
	#INPUT: array index, instantaneous VFD, MaxCFM
	#if VFD = 1000, uses CFM points
	{
		my $i = $_[0];
		my $VFD = $_[1];
		my $MaxCFM = $_[2];
		
		if( (looks_like_number($VFD))&&($VFD == 1000) )	{ return $AHU{"SupCFM"}[$i]; }
		elsif( (looks_like_number($VFD))&&($VFD == 1010) )	{ return $AHU{"CFM"}[$i]; }
		else
		{
			if(looks_like_number($VFD))	{return $VFD*$MaxCFM*.01;}
			else {return "NULL";}
		}
	}
	sub MATrat  #this calculates the expected MAT at 95% RAT and 5% OAT
				#copy this: MATrat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)
	{
		my $OADtb = $_[0];
		my $MADtb = $_[1];
		my $OADmin = $_[2];
		my $OADmax = $_[3];
		my $Leaky_Dampdb = $_[4];
		
		if(looks_like_number($OADtb)&&looks_like_number($MADtb))
		{
			return ($OADtb*(($OADmin+$Leaky_Dampdb)/100))+($MADtb*(($OADmax-$Leaky_Dampdb)/100));
		}
		elsif(looks_like_number($OADtb)&&!looks_like_number($MADtb)) {return $OADtb;}
		elsif(!looks_like_number($OADtb)&&looks_like_number($MADtb)) {return $MADtb;}
		else { return 0; }
	}

	sub MAToat  #this calculates the expected MAT at 95% OAT and 5% RAT. The % is based on damper db 
				#copy this: MAToat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)
	{
		my $OADtb = $_[0];
		my $MADtb = $_[1];
		my $OADmin = $_[2];
		my $OADmax = $_[3];
		my $Leaky_Dampdb = $_[4];
			
		if(looks_like_number($OADtb)&&looks_like_number($MADtb))
		{
			return ($OADtb*(($OADmax-$Leaky_Dampdb)/100))+($MADtb*(($OADmin+$Leaky_Dampdb)/100));
		}
		elsif(looks_like_number($OADtb)&&!looks_like_number($MADtb)) {return $OADtb;}
		elsif(!looks_like_number($OADtb)&&looks_like_number($MADtb)) {return $MADtb;}
		else { return 0; }
	}

	sub Colder  #if it is colder outside, prioritizes enthalpy
				#copy this: Colder($i)
	{
	#INPUT: array index
	#OUTPUT: true false
		my $i = $_[0];
		if( exists $AHU{"OAE"} && exists $AHU{"RAE"} ) { return ($AHU{"OAE"}[$i]<$AHU{"RAE"}[$i]); }
		elsif( exists $AHU{"OAT"} && exists $AHU{"RAT"} )  { return ($AHU{"OAT"}[$i]<$AHU{"RAT"}[$i]); }
		elsif( exists $global{"OAE"} && exists $AHU{"RAE"} ) { return ($global{"OAE"}[$i]<$AHU{"RAE"}[$i]); }
		elsif( exists $global{"OAT"} && exists $AHU{"RAT"} )  { return ($global{"OAT"}[$i]<$AHU{"RAT"}[$i]); }  		
		else {return 0;}
	}
	
	sub Warmer  #if it is warmer outside, prioritizes enthalpy
				#copy this: Warmer($i)
	{
		my $i = $_[0];
		if( exists $AHU{"OAE"} && exists $AHU{"RAE"} ) { return ($AHU{"OAE"}[$i]>$AHU{"RAE"}[$i]); }
		elsif( exists $AHU{"OAT"} && exists $AHU{"RAT"} ) { return ($AHU{"OAT"}[$i]>$AHU{"RAT"}[$i]);}
		elsif( exists $global{"OAE"} && exists $AHU{"RAE"} ) { return ($global{"OAE"}[$i]<$AHU{"RAE"}[$i]); }
		elsif( exists $global{"OAT"} && exists $AHU{"RAT"} )  { return ($global{"OAT"}[$i]<$AHU{"RAT"}[$i]);} 
		else {return 0;}

	}
	
	
	#From AHU/Standard Naming
	our @SFS = SetPlainArray("SFS");
	our @SCH = SetPlainArray("SCH");
	our @OCC = SetPlainArray("OCC");
	
	#Valves
	
	#Dampers
	our @OAD = SetPlainArray("OAD");
	our @RAD = SetPlainArray("RAD");
	our @EAD = SetPlainArray("EAD");
	our @MAD = SetPlainArray("MAD");
	#Lonely temps
	our @MAT = SetPlainArray("MAT");	
	our @PHT = SetPlainArray("PHT");
	
	#Paired temps/enthalpies
	our @SAT = SetPlainArray("SAT");
		our @SATSP = SetPlainArray("SATSP");
	our @RAT = SetPlainArray("RAT");
		our @RAE = SetPlainArray("RAE");
		
	#The below will use AHUside OA sensors. If these are not defined, it will try to use the global values.
	our @OAT = SetPlainArray("OAT");
	our @OAE = SetPlainArray("OAE");
	our @OAH = SetPlainArray("OAH");

	our @DSP = SetPlainArray("DSP");
		our @DSPSP = SetPlainArray("DSPSP");
		
	#Conversion factors
	our $ConvGas = looks_like_number($AHUinfo{$sitename}{$AHUname}{"ConvGas"}) ? $AHUinfo{$sitename}{$AHUname}{"ConvGas"} : 0;
	our $ConvSteam = looks_like_number($AHUinfo{$sitename}{$AHUname}{"ConvSteam"}) ? $AHUinfo{$sitename}{$AHUname}{"ConvSteam"} : 0;
	our $ConvElec = looks_like_number($AHUinfo{$sitename}{$AHUname}{"ConvElec"}) ? $AHUinfo{$sitename}{$AHUname}{"ConvElec"} : 0;
	our $DollarGas = looks_like_number($AHUinfo{$sitename}{$AHUname}{"DollarGas"}) ? $AHUinfo{$sitename}{$AHUname}{"DollarGas"} : 0;
	our $DollarSteam = looks_like_number($AHUinfo{$sitename}{$AHUname}{"DollarSteam"}) ? $AHUinfo{$sitename}{$AHUname}{"DollarSteam"} : 0;
	our $DollarElec = looks_like_number($AHUinfo{$sitename}{$AHUname}{"DollarElec"}) ? $AHUinfo{$sitename}{$AHUname}{"DollarElec"} : 0;

	#Per AHU Constants
	our $MaxCFM = $AHUinfo{$sitename}{$AHUname}{"MaxCFM"}; #CFMs
	our $HP = $AHUinfo{$sitename}{$AHUname}{"HP"};

	
	our $OADminSig = $AHUinfo{$sitename}{$AHUname}{"OADminSig"};
		our $OADmaxSig = $AHUinfo{$sitename}{$AHUname}{"OADmaxSig"};
	our $OADminPer = $AHUinfo{$sitename}{$AHUname}{"OADminPer"};
		our $OADmaxPer = $AHUinfo{$sitename}{$AHUname}{"OADmaxPer"};
	our $OADtb = $AHUinfo{$sitename}{$AHUname}{"OADtb"};
		our $OADta = $AHUinfo{$sitename}{$AHUname}{"OADta"};
	our $MADtb = $AHUinfo{$sitename}{$AHUname}{"MADtb"};
		our $MADta = $AHUinfo{$sitename}{$AHUname}{"MADta"};
	
		
	foreach my $name (keys(%AHU))
	{   
		if($name =~ m/^(CCV|PHV|RHV)(\d)*$/)
		{
			$AHUmap->addValve 	(	$name,
									$AHUinfo{$sitename}{$AHUname}{$name."tb"},
									$AHUinfo{$sitename}{$AHUname}{$name."ta"},
									$AHUinfo{$sitename}{$AHUname}{$name."min"},
									$AHUinfo{$sitename}{$AHUname}{$name."max"},
									$AHUinfo{$sitename}{$AHUname}{$name."EngyType"}
								);
		}
		if($name =~ m/^(OAD|MAD)(\d)*$/)
		{
			$AHUmap->addDamper 	(	$name,
									$AHUinfo{$sitename}{$AHUname}{$name."tb"},
									$AHUinfo{$sitename}{$AHUname}{$name."ta"},
									$AHUinfo{$sitename}{$AHUname}{$name."minPer"},
									$AHUinfo{$sitename}{$AHUname}{$name."maxPer"},
									$AHUinfo{$sitename}{$AHUname}{$name."minSig"},
									$AHUinfo{$sitename}{$AHUname}{$name."maxSig"},
									"Damper"
								);
		}
		if($name =~ m/^((SFS(\d)*)|(RFS(\d)*))$/)
		{
			$AHUmap->addFan($name);
		}
		if($name =~ m/^SupVFD(\d)*$/)
		{
			$AHUmap->addVFD		(	$name,
									$AHUinfo{$sitename}{$AHUname}{$name."min"},
									$AHUinfo{$sitename}{$AHUname}{$name."max"}
								);
		}
	}	
	$AHUmap->popPaths();
	print Dumper \$AHUmap;
	
	if ( (!@OAD)&&(@MAD) )
	{
		print DIAG "\tInterpolated OAD using max and min conversion: $AHUname\n";
		my $flag = 0;
		for (my $i = 0; $i < scalar @MAD; $i++)
		{
			if ( looks_like_number($MAD[$i]) )
			{
				$OAD[$i] = PerFudge($OADmaxSig,$OADminSig,$MAD[$i]) ;
			}
			else 
			{
				$OAD[$i] = "NULL";
			}
		}
	}

	if (@OAD)
	{
		my $flag = 0;
		for (my $i = 0; $i < scalar @MAD; $i++)
		{
			if ( looks_like_number($OAD[$i]) )
			{
				$OAD[$i] = PerFudge($OADmaxSig,$OADminSig,$OAD[$i]) ;	
				
				if( $OAD[$i] < $OADminPer )
				{
					$flag = 1;
					$OAD[$i] = $OADminPer;
				}
				if( $OAD[$i] > $OADmaxPer )
				{
					$flag = 1;
					$OAD[$i] = $OADmaxPer;
				}
			}
		}
		if ($flag == 1) { print DIAG "\tDamper points out of range. Used Max and/or min instead for $AHUname\n"; }
	}
	
	#sub thisfucker
	#fixes 100% OA units for the MAT...makes it into OAT
	#{
	if( $AHUinfo{$sitename}{$AHUname}{"MADtb"} eq "N/A" )	#this means its an 100% OA unit
	{
		if ( $AHUinfo{$sitename}{$AHUname}{"OADta"} =~ m/NODE/ )	
		{
			@MAT = SetPlainArray("OAT");	
			$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}} = \@MAT;
			print $AHUinfo{$sitename}{$AHUname}{"OADta"}." 100% OA no sense".$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}}." ".\@MAT." ".$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}}[-1]."\n";
		}	
		elsif($AHUinfo{$sitename}{$AHUname}{"OADta"} !~ "N/A")	#this is the case where the unit is 100% OA, but there is a sensor after the damper.
		{
			 @MAT = SetPlainArray($AHUinfo{$sitename}{$AHUname}{"OADta"});
			 print $AHUinfo{$sitename}{$AHUname}{"OADta"}." 100% OA sense".$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}}." ".\@MAT."\n";
			 #%AHU entry on OADta should be defined in this case.
		}
		else	#unit has no dampers
		{
			@MAT = SetPlainArray($AHUmap->getvtb(${$AHUmap->findFirsts}[0]));	#get the first first valves tb and set that equal to the MAT
			$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}} = \@MAT;
			print $AHUinfo{$sitename}{$AHUname}{"OADta"}."No Dampers!".$AHU{$AHUinfo{$sitename}{$AHUname}{"OADta"}}." ".\@MAT."\n";
		}
	}
	print Dumper (keys %AHU);
	#}
	our @MADtb = SetPlainArray($AHUinfo{$sitename}{$AHUname}{"MADtb"});		#this is cause im hot
	our @MADta = SetPlainArray($AHUinfo{$sitename}{$AHUname}{"MADta"});		#this is cause im hot
	our @OADtb = SetPlainArray($AHUinfo{$sitename}{$AHUname}{"OADtb"});		#this is cause this is cause
	our @OADta = SetPlainArray($AHUinfo{$sitename}{$AHUname}{"OADta"});		#this is cause im hot
																					#no but its cause AHU{"NODExyz"} is now defined, so i've defined these here.
																					#this should fix issues with future definitions
	
	our $DSPdb = $AHUinfo{$sitename}{$AHUname}{"DSPdb"};
	
	our $DATDev_Vlvdb = $AHUinfo{$sitename}{$AHUname}{"DATDev_Vlvdb"};
	our $Leaky_Vlvdb = $AHUinfo{$sitename}{$AHUname}{"Leaky_Vlvdb"};
	our $SimHC_Vlvdb = $AHUinfo{$sitename}{$AHUname}{"SimHC_Vlvdb"};
	our $Econ_Vlvdb = $AHUinfo{$sitename}{$AHUname}{"Econ_Vlvdb"};
	
	our $DATDev_Tempdb = $AHUinfo{$sitename}{$AHUname}{"DATDev_Tempdb"};
	our $Leaky_Tempdb = $AHUinfo{$sitename}{$AHUname}{"Leaky_Tempdb"};
	our $SimHC_Tempdb = $AHUinfo{$sitename}{$AHUname}{"SimHC_Tempdb"};
	our $Econ_Tempdb = $AHUinfo{$sitename}{$AHUname}{"Econ_Tempdb"};
	
	our $Leaky_Dampdb = $AHUinfo{$sitename}{$AHUname}{"Leaky_Dampdb"};
	our $Econ_Dampdb = $AHUinfo{$sitename}{$AHUname}{"Econ_Dampdb"};
	
	our $Econ_Enthdb = $AHUinfo{$sitename}{$AHUname}{"Econ_Enthdb"};
	our $Econ_EnthSP = $AHUinfo{$sitename}{$AHUname}{"Econ_EnthSP"};
	
	our $Econ_ClimateSP = $AHUinfo{$sitename}{$AHUname}{"Econ_ClimateSP"};
	
	##VVAnalytic Equations! They use a lot of the blood brain barrier things, so the should be here.VV
	
	# sub activeCheckForDATDev
	# PURPOSE: Check points needed for DATDev
	#
	# INPUTS: 
	#		PARAMETERS:
	#			index ($i), $CFM
	#		GLOBALS:
	#			$AHUmap, %AHU, %AHUinfo
	# RETURN: Hash of {"Point" -> Status} 
	#		where status is the looks_like_number on that timestamp for that point    
	#	hash also has a kay "activePercenage, which is 0 if req points are missing.
	#
	sub activeCheckForDATDev
	{
		my $i = $_[0];
		my $CFM = &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM);
		my %active = (	#these should be 100% REQUIRED points. Without these points, there's no point of going further
			"MAT" => ( looks_like_number($MAT[$i]) > 0),	#MAT
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"CFM" => ( looks_like_number($CFM) > 0)
		);
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				$active{"activePercentage"} = 0;
			}
		}
		my @fatalPath;
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			unless($active{$sDAT}&&$active{$sDATSP})	#if you're missing either of DAT or DATSP
			{
				push @fatalPath, 1;	#if these are all fatal, then analytic is fatal, and returns 0
				next;	#no point of continuing after this.
			}
			my @fatalValve;
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
				unless( $active{$AHUmap->getvta($valve)}&&$active{$AHUmap->getvtb($valve)}&&$active{$valve} )	#if you are missing any one of tb or ta or valve signal
				{
					push @fatalValve, 1;	#if these are all fatal, then path is fatal
				}
				else
				{
					push @fatalValve, 0;
				}
			}
			my $fatalvFailure = 0;
			foreach my $fatal (@fatalValve)
			{
				$fatalvFailure += $fatal;
			}
			if($fatalvFailure == scalar(@fatalValve))	#only if all valve paths were fatal
			{
				push @fatalPath, 1;
			}
			else
			{
				push @fatalPath, 0;
			}
		}
		my $fatalpFailure = 0;
		foreach my $fatal (@fatalPath)
		{
			$fatalpFailure += $fatal;
		}
		
		if($fatalpFailure == scalar(@fatalPath))
		{
			$active{"activePercentage"} = 0;
		}
		if(exists $active{"activePercentage"})	#since this will only exist if there has been
			#a previous required point failure, this will return activePercentage = 0
			#this ensures this hash will always have all the points the
			#analytic uses for calculation. Useful for diagnostic output
		{
			
			return %active;
		}
		my $activePercentageNumerator = 0;
		my $activePercentageDenominator = (scalar (keys(%active)));
		foreach my $key (keys(%active))
		{
			$activePercentageNumerator += $active{$key};
		}

		$active{"activePercentage"} = $activePercentageNumerator/$activePercentageDenominator;
		return %active;
	}
	
	# sub activeCheckForDATDev
	# PURPOSE: Check points needed for DATDev
	#
	# INPUTS: 
	#		PARAMETERS:
	#			index ($i), $CFM
	#		GLOBALS:
	#			$AHUmap, %AHU, %AHUinfo
	# RETURN: Hash of {"Point" -> Status} 
	#		where status is the looks_like_number on that timestamp for that point    
	#	hash also has a kay "activePercenage, which is 0 if req points are missing.
	#
	sub activeCheckForOutOfOcc
	{
		my $i = $_[0];
		my $CFM = &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM);
		my $VFD = &MakeVFD($i,REALLYMakeVFD($i, $MaxCFM));
		
		my %active = (
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0)
		);

		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				$active{"activePercentage"} = 0;
			}
		}
		$active{"VFD"} = ( looks_like_number($VFD) > 0);	#MAT
		$active{"CFM"} = ( looks_like_number($CFM) > 0);
		
		unless ($active{"VFD"}||$active{"CFM"})	#if both are false. DeMorgans ftw
		{
			$active{"activePercentage"} = 0;
		}
		
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
			}
		}
		foreach my $key (keys(%active))
		{
			$savings{"active"} += $active{$key};
		}

		if(exists $active{"activePercentage"})	#since this will only exist if there has been
			#a previous required point failure, this will return activePercentage = 0
			#this ensures this hash will always have all the points the
			#analytic uses for calculation. Useful for diagnostic output
		{
			
			return %active;
		}
		my $activePercentageNumerator = 0;
		my $activePercentageDenominator = (scalar (keys(%active)));
		foreach my $key (keys(%active))
		{
			$activePercentageNumerator += $active{$key};
		}

		$active{"activePercentage"} = $activePercentageNumerator/$activePercentageDenominator;
		return %active;
	}
	
	# sub sandwichSensorFudger
	# PURPOSE: Imagine the following case: (there is no MAD/RAT)
	#	OAD --- PHV --- CCV
	#	    MAT		NODE1	SAT
	# this function will replace AHUmap entries such that CCVtb = MAT and PHVta = SAT.
	# This should probably only work with DATDev... correct me if i'm wrong.
	# If this subroutine is used, the &sandwichSensorUnfudger must be called with 
	# the output of this function passed into it. This function changes AHUmap permanently, 
	# and these changes must be reverted. Also note that MAT is completely weird to have here,
	# but stfu.
	#
	# INPUTS: 
	#		GLOBALS:
	#			$AHUmap
	# RETURN: Translation hash REFERENCE. $returnRealFakeTranslationHash
	#		this hash REFERENCE has 4 keys, realtb, realta, faketb, faketa.   
	#	these keys act as a cypher of sorts to change back to the previous configuration.
	#	This output MUST be used as an input into sandwichSensorUnfudger to revert changes to AHUmap
	
	sub sandwichSensorFudger
	{
		my %returnRealFakeTranslationHash = 
		(
			"realtb" => {},
			"realta" => {},
			"faketa" => {},
			"faketb" => {},
		);
		foreach my $valve ($AHUmap->getVlv)
		{
			if(   (  ( scalar (@{$AHUmap->prevValve($valve)}) ) == 1  )&&($AHUmap->getvtb($valve) =~ m/NODE/)   )    #if there is only one valve before it, and the tb m/NODE/...
			{
				my $prevValve = $AHUmap->prevValve($valve)->[0];
				unless (  (( $AHUmap->getvtb($valve) eq $MADta )||( $prevValve eq "OAD" )) || (  ( ($valve =~ m/C/)&&($prevValve =~m/C/) )||( ($valve =~ m/H/)&&($prevValve =~m/H/) )  ) ) 
				#make sure it doesn't fudge nodes with mix air ducts, or does anything weird with how OAT is treated previously. ALSO that the valves aren't the same type
				{
					$returnRealFakeTranslationHash{"realtb"}->{$valve} = $AHUmap->getvtb($valve);
					$returnRealFakeTranslationHash{"faketb"}->{$valve} = $AHUmap->getvtb($prevValve);
				}
			}
			if(   (  ( scalar (@{$AHUmap->nextValve($valve)}) ) == 1  )&&($AHUmap->getvta($valve) =~ m/NODE/)   )    #if there is only one valve before it, and the ta m/NODE/...
			{
				my $nextValve = $AHUmap->nextValve($valve)->[0];
				unless ( ( $AHUmap->getvta($valve) eq $MADta ) || (  ( ($valve =~ m/C/)&&($nextValve =~m/C/) )||( ($valve =~ m/H/)&&($nextValve =~m/H/) )  ) ) 
				#make sure it fudges nodes with mix air ducts. ALSO that the valves aren't the same type
				{
					$returnRealFakeTranslationHash{"realta"}->{$valve} = $AHUmap->getvta($valve);
					$returnRealFakeTranslationHash{"faketa"}->{$valve} = $AHUmap->getvta($nextValve);
				}	
			}
		}
		foreach my $valve (  keys( %{$returnRealFakeTranslationHash{"faketb"}} )  )	#replaces the ta and tbs with their actual quantities
		{
			$AHUmap->setvtb($valve, $returnRealFakeTranslationHash{"faketb"}->{$valve});
		}
		foreach my $valve (  keys( %{ $returnRealFakeTranslationHash{"faketa"} } )  )
		{
			$AHUmap->setvta($valve, $returnRealFakeTranslationHash{"faketa"}->{$valve});
		}
		return \%returnRealFakeTranslationHash;
	}
	
	# sub sandwichSensorUnfudger
	# PURPOSE: Reverts changes done by &sandwichSensorFudger
	#
	# INPUTS: 
	#		PARAMETERS:
	#			$returnRealFakeTranslationHash
	#		GLOBALS:
	#			$AHUmap
	# RETURN: void
	#
	
	sub sandwichSensorUnfudger
	{
		my $inputRealFakeTranslationHash = $_[0];
		foreach my $valve (keys(%{ $inputRealFakeTranslationHash->{"realtb"} }))	#replaces the ta and tbs with their actual quantities
		{
			$AHUmap->setvtb($valve, $inputRealFakeTranslationHash->{"realtb"}->{$valve});
		}
		foreach my $valve (keys(%{ $inputRealFakeTranslationHash->{"realta"}}))
		{
			$AHUmap->setvta($valve, $inputRealFakeTranslationHash->{"realta"}->{$valve});
		}
		return;
	}
	
	sub DATDevH #Dennis Approved, OATta -> MAT changes
	#DAT Deviation
	#working
	#use this: &DATDevH($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{

		my $i = $_[0];
		my $CFM = $_[1];
		
		my %BUCKETZ;
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);

		if( @SCH&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&($SCH[$i])&&( looks_like_number($CFM) ) )
			{	#You can haz Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$BUCKETZ{$PHV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$BUCKETZ{$CCV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$BUCKETZ{$RHV} = 0;
				}
				#Everyone can haz Bucketz!!!
				
				foreach my $lists ($AHUmap->getpaths)
				{
						# print  $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i];    		#DAT
						# print  $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i];   	#DATSP
						# print  $OADta[$i]; 			#MAT
																#DAT															#DATSP
					if ( looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i])&&looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])
					&&looks_like_number($MAT[$i]) )
													#MAT
					{
																	#DAT > DATSP+db
						if ( ($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i] > ($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i] + $DATDev_Tempdb)) )
						{
							my $heating = 0;
							
							foreach my $potatoes (@{$lists})
							{
								if ($potatoes =~ m/HV/)
								{
									if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
									&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $DATDev_Tempdb))&&($AHU{$potatoes}[$i] > ($AHUmap->getvmin($potatoes) + $DATDev_Vlvdb))	) ####
									{
										$heating = 1;
									}
								}
							}
																	   #MAT > DATSP
							if ( ($MAT[$i] > $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])&&$heating )
							{
								foreach my $potatoes (@{$lists})
								{
									if ($potatoes =~ m/HV/) #all heating is waste
									{
										if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
											&&looks_like_number($CFM)&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < $AHU{ $AHUmap->getvta($potatoes) }[$i])	) 
										{	
											if ($BUCKETZ{$potatoes} < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]) )
											{
												$BUCKETZ{$potatoes} = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]);
											}
										}
									}
								}
							}
																	   #MAT < DATSP
							if ( ($MAT[$i] < $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])&&$heating )
							{	 
								my $ReqEn = ( $MAT[$i] - $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]); #how much energy is required to hit set point
								
								foreach my $potatoes (@{$lists})
								{
									if ($potatoes =~ m/HV/)
									{
										if ( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
											&&looks_like_number($CFM)&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < $AHU{ $AHUmap->getvta($potatoes) }[$i] )	) 
										{	
											my $deltaT = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]); #temp change across the valve
											
											$ReqEn += $deltaT; #by adding deltaT to the required energy you are able to tell how much (if any) of the energy transfer across the valve is waste
											
											if ($ReqEn > $deltaT)
											{
												if ($BUCKETZ{$potatoes} < $deltaT )
												{
													$BUCKETZ{$potatoes} = $deltaT;
												}
											}
											elsif ( ($ReqEn>0)&&($ReqEn<=$deltaT) )
											{
												if ($BUCKETZ{$potatoes} < $ReqEn )
												{
													$BUCKETZ{$potatoes} = $ReqEn; 
												}
											}
											else{}
										}
									}
								}
							}
						}
					}
				}
				#Empty dat Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*$BUCKETZ{$PHV};
				}
				#Empty dat Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*$BUCKETZ{$CCV};
				}
				#Empty dat Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*$BUCKETZ{$RHV};
				}
			}
		}
		
		return %savings;
	}
	
	sub DATDevC #Dennis Approved, OATta -> MAT changes
		#DAT Deviation
		#working
		#use this: &DATDevC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{
		my $i = $_[0];
		my $CFM = $_[1];
		
		my %BUCKETZ;
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
						
		if( @SCH&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&($SCH[$i])&&( looks_like_number($CFM) ) )
			{	#You can haz Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$BUCKETZ{$PHV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$BUCKETZ{$CCV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$BUCKETZ{$RHV} = 0;
				}
				#Everyone can haz Bucketz!!!

				foreach my $lists ($AHUmap->getpaths)
				{
						# print  $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i];    		#DAT
						# print  $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i];   	#DATSP
						# print  $OADta[$i]; print "\n";			#MAT
						# print $MAT[$i]; print "\n";	
												#DAT															#DATSP
					if ( looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i])&&looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])
					&&looks_like_number($MAT[$i]) )
					{							#MAT
																   #DAT < DATSP-db
						if ( $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i] < ($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i] - $DATDev_Tempdb) )
						{
							my $cooling = 0;
							
							foreach my $potatoes (@{$lists})
							{
								if ($potatoes =~ m/CCV/)
								{
									if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
									&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > ($AHU{ $AHUmap->getvta($potatoes) }[$i] + $DATDev_Tempdb))&&($AHU{$potatoes}[$i] > ($AHUmap->getvmin($potatoes) + $DATDev_Vlvdb))	) ####
									{
										$cooling = 1;
									}
								}
							}
						
																		#MAT > DATSP
							if ( ($MAT[$i] > $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])&&$cooling )
							{
								my $ReqEn = ( $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]  - $MAT[$i]   ); #how much energy is required to hit set point
								
								foreach my $potatoes (@{$lists})
								{
									if ($potatoes =~ m/CCV/) 
									{
										if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
											&&looks_like_number($CFM)&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > $AHU{ $AHUmap->getvta($potatoes) }[$i])	) 
										{
											my $deltaT = ( $AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i] ); #temp change across the valve
											
											$ReqEn += $deltaT; #by adding deltaT to the required energy you are able to tell how much (if any) of the energy transfer across the valve is waste
											
											if ($ReqEn > $deltaT)
											{
												if ($BUCKETZ{$potatoes} < $deltaT )
												{
													$BUCKETZ{$potatoes} = $deltaT;
												}
											}
											elsif ( ($ReqEn>0)&&($ReqEn<=$deltaT) )
											{
												if ($BUCKETZ{$potatoes} < $ReqEn )
												{
													$BUCKETZ{$potatoes} = $ReqEn;
												}
											}
											else{}
										}
									}
								}
							}
																	   #MAT < DATSP
							if ( ($MAT[$i] < $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])&&$cooling )
							{
								foreach my $potatoes (@{$lists})
								{
									if ($potatoes =~ m/CCV/) #all cooling is waste
									{
										if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
											&&looks_like_number($CFM)&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > $AHU{ $AHUmap->getvta($potatoes) }[$i])  ) 
										{
											if ($BUCKETZ{$potatoes} < ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]) )
											{
												$BUCKETZ{$potatoes} = ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]);
											}
										}
									}
								}
							}
							
						}
					}
				}
				#Empty dat Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*$BUCKETZ{$PHV};
				}
				#Empty dat Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*$BUCKETZ{$CCV};
				}
				#Empty dat Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*$BUCKETZ{$RHV};
				}
			}
		}

		return %savings;
	}
	
	sub OutofOcc #Dennis Approved i think?
	#use this:	&OutofOcc($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM), &REALLYMakeVFD($i, $MaxCFM))
	#working
	{
		my $i = $_[0];
		my $CFM = $_[1];
		my $VFD = $_[2];
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
						

		if( @SCH&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&!($SCH[$i])&&( looks_like_number($CFM) ) )
			{
				foreach my $PHV ($AHUmap->getPHV)
				{
					if( looks_like_number($AHU{$PHV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($PHV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($PHV) }[$i])&&looks_like_number($CFM)
						&&($AHU{ $AHUmap->getvtb($PHV) }[$i] < $AHU{ $AHUmap->getvta($PHV) }[$i])	) 
						{
							$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*($AHU{ $AHUmap->getvta($PHV) }[$i] - $AHU{ $AHUmap->getvtb($PHV) }[$i]);
						}
				}
				
				foreach my $CCV ($AHUmap->getCCV)
				{
					if( looks_like_number($AHU{$CCV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($CCV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($CCV) }[$i])&&looks_like_number($CFM)
						&&($AHU{ $AHUmap->getvtb($CCV) }[$i] > $AHU{ $AHUmap->getvta($CCV) }[$i])	) 
						{
							$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*($AHU{ $AHUmap->getvtb($CCV) }[$i] - $AHU{ $AHUmap->getvta($CCV) }[$i]);
						}
				}

				foreach my $RHV ($AHUmap->getRHV)
				{
					if( looks_like_number($AHU{$RHV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($RHV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($RHV) }[$i])&&looks_like_number($CFM)
						&&($AHU{ $AHUmap->getvtb($RHV) }[$i] < $AHU{ $AHUmap->getvta($RHV) }[$i])	) 
						{
							$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*($AHU{ $AHUmap->getvta($RHV) }[$i] - $AHU{ $AHUmap->getvtb($RHV) }[$i]);
						}
				}
				
				if( looks_like_number($VFD) )
				{	
					$savings{"elec"} += $HP*.25*$kWHP*($VFD*.01)**3;
				}
			}
		}
		
		print $ooo ",".$savings{"elec"}.",".$savings{"active"}."\n";
		return %savings;
	}

	sub LeakyDamper #Dennis Approved. This shouldn't work for 100% OA units, which is okay. The logic kinda befuddled me a bit, but i don't see there being too many issues, since there are no need for MAT specifically
	#&LeakyDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{
		my $i = $_[0];
		my $CFM = $_[1];
		
		my %BUCKETZ;
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
						
		
		
		my %active = (
			"MAT" => ( looks_like_number($MAT[$i]) > 0),	#MAT
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"CFM" => ( looks_like_number($CFM) > 0),
			"MADta" => ( looks_like_number($MADta[$i]) > 0),
			"MADtb" => ( looks_like_number($MADtb[$i]) > 0),
			"OADta" => ( looks_like_number($OADta[$i]) > 0),
			"OADtb" => ( looks_like_number($OADtb[$i]) > 0),
			"OAD" => ( looks_like_number($OAD[$i]) > 0),
		);
		
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				return %savings;
			}
		}
		my @fatalPath;
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			unless($active{$sDAT}&&$active{$sDATSP})	#if you're missing either of DAT or DATSP
			{
				push @fatalPath, 1;	#if these are all fatal, then analytic is fatal, and returns 0
				next;	#no point of continuing after this.
			}
			my @fatalValve;
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
				unless( $active{$AHUmap->getvta($valve)}&&$active{$AHUmap->getvtb($valve)}&&$active{$valve} )	#if you are missing any one of tb or ta or valve signal
				{
					push @fatalValve, 1;	#if these are all fatal, then path is fatal
				}
				else
				{
					push @fatalValve, 0;
				}
			}
			my $fatalvFailure = 0;
			foreach my $fatal (@fatalValve)
			{
				$fatalvFailure += $fatal;
			}
			if($fatalvFailure == scalar(@fatalValve))	#only if all valve paths were fatal
			{
				push @fatalPath, 1;
			}
			else
			{
				push @fatalPath, 0;
			}
		}
		my $fatalpFailure = 0;
		foreach my $fatal (@fatalPath)
		{
			$fatalpFailure += $fatal;
		}
		
		if($fatalpFailure == scalar(@fatalPath))
		{
			return %savings;
		}

		foreach my $key (keys(%active))
		{
			$savings{"active"} += $active{$key};
		}

		$savings{"active"} = $savings{"active"}/(scalar (keys(%active)));
		if( ((scalar $AHUmap->getSF) > 0)&&@SCH&&@OAD&&@OADtb&&@OADta&&@MADtb&&@MADta&&looks_like_number($CFM)&&looks_like_number(&FanOn($i))&&looks_like_number($SCH[$i])&&(&FanOn($i))&&($SCH[$i]) )	
		{
			#You can haz Bucket!!!
			foreach my $PHV ($AHUmap->getPHV)
			{
				$BUCKETZ{$PHV} = 0;
			}
			#You can haz Bucket!!!
			foreach my $CCV ($AHUmap->getCCV)
			{
				$BUCKETZ{$CCV} = 0;
			}
			#You can haz Bucket!!!
			foreach my $RHV ($AHUmap->getRHV)
			{
				$BUCKETZ{$RHV} = 0;
			}
			#Everyone can haz Bucketz!!!
				
			foreach my $lists ($AHUmap->getpaths)
			{																				
				#stuff to be used later
				my $MaxWasteH = 0;
				my $MaxWasteC = 0;				#MATrat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)  
				my $MATratEx;# = MATrat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
				my $MAToatEx;# = MAToat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);	#warning if $OADtb[$i],$MADtb[$i] don't look like numbers
												#MAToat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)
				
			
				my $OAD = PerFudge($AHUinfo{$sitename}{$AHUname}{"OADminSig"},$AHUinfo{$sitename}{$AHUname}{"OADmaxSig"},$OAD[$i]);         #minSig      $AHU{ $AHUmap->getvminSig(${$lists}[0])  }[$i]
				
				
				#is the event happening? if so calc the max possible waste
				if(looks_like_number($OAD[$i])&&looks_like_number($OADtb[$i])
					&&looks_like_number($OADta[$i])&&looks_like_number($MADtb[$i]) )	
				{
					$MATratEx = MATrat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
					$MAToatEx = MAToat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
					if( ($OAD<($AHUinfo{$sitename}{$AHUname}{"OADminPer"}+$Leaky_Dampdb)) && Colder($i) && ( $OADta[$i] < ($MATratEx-$Leaky_Tempdb) )  )
					{
						$MaxWasteH = $MATratEx - $OADta[$i];
					}
					
					if( ($OAD<($AHUinfo{$sitename}{$AHUname}{"OADminPer"}+$Leaky_Dampdb)) && Warmer($i) && ( $OADta[$i] > ($MATratEx+$Leaky_Tempdb) )   )
					{
						$MaxWasteC = $OADta[$i] - $MATratEx;
					}
					######################-^^-leaky/Stuck-vv- segregation line#################################################
				}
			
				# print  $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i];    		#DAT
				# print  $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i];   	#DATSP
				# print  $OADta[$i]; 			#MAT

				if( $MaxWasteH > 0 )
				{
					foreach my $potatoes (@{$lists})
					{
						my $waste = $MaxWasteH;
						
						if ($potatoes =~ m/HV/)
						{
							if (looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i]))
							{
								my $deltaT = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]);
								
								if ( $waste <= 0 ){}
								elsif( $waste < $deltaT)
								{
									if($BUCKETZ{$potatoes} < $waste )
									{
										$BUCKETZ{$potatoes} = $waste;
									}
								}
								else
								{
									if($BUCKETZ{$potatoes} < $deltaT )
									{
										$BUCKETZ{$potatoes} = $deltaT;
									}
								}
								
								$waste -= $deltaT
							}
						}
					}
				}
				
				if( $MaxWasteC > 0 )
				{
					foreach my $potatoes (@{$lists})
					{
						my $waste = $MaxWasteC;
						
						if ($potatoes =~ m/CCV/)
						{
							if (looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i]))
							{
								my $deltaT = ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]);
								
								if ( $waste <= 0 ){}
								elsif( $waste<$deltaT)
								{
									if($BUCKETZ{$potatoes} < $waste )
									{
										$BUCKETZ{$potatoes} = $waste;
									}
								}
								else
								{
									if($BUCKETZ{$potatoes} < $deltaT )
									{
										$BUCKETZ{$potatoes} = $deltaT;
									}
								}
								
								$waste -= $deltaT
							}
						}
					}
				}
			}
			
			#Empty dat Bucket!!!
			foreach my $PHV ($AHUmap->getPHV)
			{
				$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*$BUCKETZ{$PHV};
			}
			#Empty dat Bucket!!!
			foreach my $CCV ($AHUmap->getCCV)
			{
				$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*$BUCKETZ{$CCV};
			}
			#Empty dat Bucket!!!
			foreach my $RHV ($AHUmap->getRHV)
			{
				$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*$BUCKETZ{$RHV};
			}
			#aaaaaaw meh bucktz are empty :_(
			
		}
		
		return %savings;
	}

	sub StuckDamper #BOO-YEAH!!!........no, no more boo-yeah, fuck this code, fuck it with something long, hooked, and rusted......twice
	#works
	#use this:	&StuckDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{
		my $i = $_[0];
		my $CFM = $_[1];
		
		my %BUCKETZ;
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
		
	
		my %active = (
			"MAT" => ( looks_like_number($MAT[$i]) > 0),	#MAT
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"CFM" => ( looks_like_number($CFM) > 0),
			"MADta" => ( looks_like_number($MADta[$i]) > 0),
			"MADtb" => ( looks_like_number($MADtb[$i]) > 0),
			"OADta" => ( looks_like_number($OADta[$i]) > 0),
			"OADtb" => ( looks_like_number($OADtb[$i]) > 0),
			"OAD" => ( looks_like_number($OAD[$i]) > 0),
			"MAD" => ( looks_like_number($MAD[$i]) > 0),
		);
		
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				return %savings;
			}
		}
		my @fatalPath;
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			unless($active{$sDAT}&&$active{$sDATSP})	#if you're missing either of DAT or DATSP
			{
				push @fatalPath, 1;	#if these are all fatal, then analytic is fatal, and returns 0
				next;	#no point of continuing after this.
			}
			my @fatalValve;
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
				unless( $active{$AHUmap->getvta($valve)}&&$active{$AHUmap->getvtb($valve)}&&$active{$valve} )	#if you are missing any one of tb or ta or valve signal
				{
					push @fatalValve, 1;	#if these are all fatal, then path is fatal
				}
				else
				{
					push @fatalValve, 0;
				}
			}
			my $fatalvFailure = 0;
			foreach my $fatal (@fatalValve)
			{
				$fatalvFailure += $fatal;
			}
			if($fatalvFailure == scalar(@fatalValve))	#only if all valve paths were fatal
			{
				push @fatalPath, 1;
			}
			else
			{
				push @fatalPath, 0;
			}
		}
		my $fatalpFailure = 0;
		foreach my $fatal (@fatalPath)
		{
			$fatalpFailure += $fatal;
		}
		
		if($fatalpFailure == scalar(@fatalPath))
		{
			return %savings;
		}

		foreach my $key (keys(%active))
		{
			$savings{"active"} += $active{$key};
		}

		$savings{"active"} = $savings{"active"}/(scalar (keys(%active)));

		if( ((scalar $AHUmap->getSF) > 0)&&@SCH&&@MADtb&&@MADta&&looks_like_number($CFM)&&looks_like_number(&FanOn($i))&&looks_like_number($SCH[$i])&&(&FanOn($i))&&($SCH[$i]) )	
		{
			
			#You can haz Bucket!!!
			foreach my $PHV ($AHUmap->getPHV)
			{
				$BUCKETZ{$PHV} = 0;
			}
			#You can haz Bucket!!!
			foreach my $CCV ($AHUmap->getCCV)
			{
				$BUCKETZ{$CCV} = 0;
			}
			#You can haz Bucket!!!
			foreach my $RHV ($AHUmap->getRHV)
			{
				$BUCKETZ{$RHV} = 0;
			}
			#Everyone can haz Bucketz!!!
				
			foreach my $lists ($AHUmap->getpaths)
			{																				
				#stuff to be used later
				my $MaxWasteH = 0;
				my $MaxWasteC = 0;				#MATrat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)  
				my $MATratEx;# = MATrat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
				my $MAToatEx;# = MAToat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
												#MAToat($OADtb[$i],$MADtb[$i],$OADmin,$OADmax,$Leaky_Dampdb)
				
			
				my $OAD = PerFudge($AHUinfo{$sitename}{$AHUname}{"OADminSig"},$AHUinfo{$sitename}{$AHUname}{"OADmaxSig"},$OAD[$i]);         #minSig      $AHU{ $AHUmap->getvminSig(${$lists}[0])  }[$i]
				
				
				#is the event happening? if so calc the max possible waste
				if(looks_like_number($OAD)&&looks_like_number($OADtb[$i])
					&&looks_like_number($OADta[$i])&&looks_like_number($MADtb[$i]) )	
				{
					$MATratEx = MATrat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
					$MAToatEx = MAToat($OADtb[$i],$MADtb[$i],$AHUinfo{$sitename}{$AHUname}{"OADminPer"},$AHUinfo{$sitename}{$AHUname}{"OADmaxPer"},$Leaky_Dampdb);
					######################-^^-leaky/Stuck-vv- segregation line#################################################
					if( ($OAD>($AHUinfo{$sitename}{$AHUname}{"OADmaxPer"}-$Leaky_Dampdb)) && Warmer($i) && ( $OADta[$i] < ($MAToatEx-$Leaky_Tempdb) )   )
					{
						$MaxWasteH = $MAToatEx - $OADta[$i];
					}
					
					if( ($OAD>($AHUinfo{$sitename}{$AHUname}{"OADmaxPer"}-$Leaky_Dampdb)) && Colder($i) && ( $OADta[$i] > ($MAToatEx+$Leaky_Tempdb) )   )
					{
						$MaxWasteC = $OADta[$i] - $MAToatEx;
					}
				}
				
				# print  $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i];    		#DAT
				# print  $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i];   	#DATSP
				# print  $OADta[$i]; 			#MAT

				if( $MaxWasteH > 0 )
				{
					foreach my $potatoes (@{$lists})
					{
						my $waste = $MaxWasteH;
						
						if ($potatoes =~ m/HV/)
						{
							my $deltaT = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]);
							
							if ( $waste < 0 ){}
							elsif( $waste<$deltaT)
							{
								if($BUCKETZ{$potatoes} < $waste )
								{
									$BUCKETZ{$potatoes} = $waste;
								}
							}
							else
							{
								if($BUCKETZ{$potatoes} < $deltaT )
								{
									$BUCKETZ{$potatoes} = $deltaT;
								}
							}
							
							$waste -= $deltaT
						}
					}
				}
				
				if( $MaxWasteC > 0 )
				{
					foreach my $potatoes (@{$lists})
					{
						my $waste = $MaxWasteC;
						
						if ($potatoes =~ m/CCV/)
						{
							my $deltaT = ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]);
							
							if ( $waste < 0 ){}
							elsif( $waste<$deltaT)
							{
								if($BUCKETZ{$potatoes} < $waste )
								{
									$BUCKETZ{$potatoes} = $waste;
								}
							}
							else
							{
								if($BUCKETZ{$potatoes} < $deltaT )
								{
									$BUCKETZ{$potatoes} = $deltaT;
								}
							}
							
							$waste -= $deltaT
						}
					}
				}
			}
			
			#Empty dat Bucket!!!
			foreach my $PHV ($AHUmap->getPHV)
			{
				$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*$BUCKETZ{$PHV};
			}
			#Empty dat Bucket!!!
			foreach my $CCV ($AHUmap->getCCV)
			{
				$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*$BUCKETZ{$CCV};
			}
			#Empty dat Bucket!!!
			foreach my $RHV ($AHUmap->getRHV)
			{
				$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*$BUCKETZ{$RHV};
			}
			#aaaaaaw meh bucktz are empty :_(
			
		}
		
		return %savings;
	}

	sub DSPDev #Dennis Approved, thank god we have ONE FUCKING SIMPLE ANALYTIC, gdamn. And its cuz we fudged stuff, eguhh
	#use this:	&DSPDev($i, &REALLYMakeVFD($i, $MaxCFM))
	#working
	#will return a hash of savings per time stamp
	{
		my $i = $_[0];
		my $VFD = $_[1];
		print $dbg "\nFan: ".&FanOn($i)."SCH: ".$SCH[$i]."DSP: ".$DSP[$i]."DSPSP: ".$DSPSP[$i]."VFD: ".$VFD."HP: ".$HP."DSPdb: ".$DSPdb;
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
		my %active = (
			"DSP" => ( looks_like_number($DSP[$i]) > 0),
			"DSPSP" => ( looks_like_number($DSPSP[$i]) > 0),
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"VFD" => ( looks_like_number($VFD) > 0),
			"HP" => ( looks_like_number($HP) > 0),
			"DSPdb" => ( looks_like_number($DSPdb) > 0)
		);
		
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				print $dbg Dumper (keys %AHU);
				print $dbg Dumper \%active;
				return %savings;
			}
		}

		$savings{"active"} = 1;

		if( @SCH&&@DSP&&@DSPSP&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&($SCH[$i])&&looks_like_number($DSP[$i])
			&&looks_like_number($DSPSP[$i])&&looks_like_number($VFD) )
			{
				if ( ($DSP[$i] > ($DSPSP[$i]+$DSPdb))&&($DSPSP[$i] > 0)&&(&FanOn($i))&&($SCH[$i]) )
				{
					$savings{"elec"} += (($VFD/100)**3)*$HP*0.25*$kWHP*(1-($DSPSP[$i]/$DSP[$i])**1.5);
				}
			}
		}
			print $dbg "Savings: ".$savings{"elec"};
			return %savings;
	}


	sub SimHC #Dennis Approved, OATta -> MAT changes
	#Simultaneous Heating and Cooling
	#working
	#&SimHC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{
		my $i = $_[0];
		my $CFM = $_[1];

		
		my $heating = 0;
		my $cooling = 0;	
		
		my %BUCKETZ;
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
		my %active = (
			"MAT" => ( looks_like_number($MAT[$i]) > 0),	#MAT
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"CFM" => ( looks_like_number($CFM) > 0)
		);
		
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				return %savings;
			}
		}
		
		$active{"RAT"} = looks_like_number($RAT[$i]) > 0;	#RAT
		
		my @fatalPath;
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			unless($active{$sDAT}&&$active{$sDATSP})	#if you're missing either of DAT or DATSP
			{
				push @fatalPath, 1;	#if these are all fatal, then analytic is fatal, and returns 0
				next;	#no point of continuing after this.
			}
			my @fatalValve;
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
				unless( $active{$AHUmap->getvta($valve)}&&$active{$AHUmap->getvtb($valve)}&&$active{$valve} )	#if you are missing any one of tb or ta or valve signal
				{
					push @fatalValve, 1;	#if these are all fatal, then path is fatal
				}
				else
				{
					push @fatalValve, 0;
				}
			}
			my $fatalvFailure = 0;
			foreach my $fatal (@fatalValve)
			{
				$fatalvFailure += $fatal;
			}
			if($fatalvFailure == scalar(@fatalValve))	#only if all valve paths were fatal
			{
				push @fatalPath, 1;
			}
			else
			{
				push @fatalPath, 0;
			}
		}
		my $fatalpFailure = 0;
		foreach my $fatal (@fatalPath)
		{
			$fatalpFailure += $fatal;
		}
		
		if($fatalpFailure == scalar(@fatalPath))
		{
			return %savings;
		}

		foreach my $key (keys(%active))
		{
			$savings{"active"} += $active{$key};
		}

		$savings{"active"} = $savings{"active"}/(scalar (keys(%active)));
		if( @SCH&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number($CFM) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&($SCH[$i]) )
			{	#You can haz Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$BUCKETZ{$PHV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$BUCKETZ{$CCV} = 0;
				}
				#You can haz Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$BUCKETZ{$RHV} = 0;
				}
				#Everyone can haz Bucketz!!!
				
				foreach my $lists ($AHUmap->getpaths)
				{
				
					foreach my $potatoes (@{$lists})
					{
						if ($potatoes =~ m/HV/)
						{
							if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
								&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $SimHC_Tempdb))&&($AHU{$potatoes}[$i] > ($AHUmap->getvmin($potatoes) + $SimHC_Vlvdb))	) ####
								{
									$heating = 1;
								}
						}
						
						if ($potatoes =~ m/CCV/)
						{
							if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
								&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > ($AHU{ $AHUmap->getvta($potatoes) }[$i] + $SimHC_Tempdb))&&($AHU{$potatoes}[$i] > ($AHUmap->getvmin($potatoes) + $SimHC_Vlvdb))	) 
								{
									$cooling = 1;
								}
						}
						
						if(@OAT&&@RAT&&looks_like_number($AHU{$AHUmap->getOAD}[$i]))
						{
							if (looks_like_number($OAT[$i])&&looks_like_number($RAT[$i]))
							{
								if (  ($OAT[$i]<($RAT[$i] - $SimHC_Tempdb))&&( $AHU{$AHUmap->getOAD}[$i] > ($AHUinfo{$sitename}{$AHUname}{"OADminPer"} + $SimHC_Vlvdb) )  )
								{
									$cooling = 1;
								}
							}	
						}
					}
					# print  $AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i];    		#DAT
					# print  $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i];   	#DATSP
					# print  $OADta[$i]; 			#MAT
					
					#################### Above tells if it's hating and cooling ################ Below tells what to do if heating and cooling ##############

							# H + C												#DATSP											#MAT
					if($heating&&$cooling&&looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i])&&looks_like_number($MAT[$i])  )
					{
						#if 	  MAT < DATSP
						if ( $MAT[$i] < $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i] ) 
						{
							my $ReqEn = ($MAT[$i]- $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]); #how much energy is required to hit set point
							
							foreach my $potatoes (@{$lists})
							{
								if ($potatoes =~ m/CCV/) #all cooling is waste
								{
									if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
										&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > ($AHU{ $AHUmap->getvta($potatoes) }[$i] + $SimHC_Tempdb))	) 
									{
										if ($BUCKETZ{$potatoes} < ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]) )
										{
											$BUCKETZ{$potatoes} = ($AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i]);
										}
									}
								}
								
								if ($potatoes =~ m/HV/)
								{
									if ( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
										&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $SimHC_Tempdb))	) 
									{
										my $deltaT = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]); #temp change across the valve
										
										$ReqEn += $deltaT; #by adding deltaT to the required energy you are able to tell how much (if any) of the energy transfer across the valve is waste
										
										if ($ReqEn > $deltaT)
										{ 
											if ($BUCKETZ{$potatoes} < $deltaT )
											{
												$BUCKETZ{$potatoes} = $deltaT;
											}
										}
										elsif ( ($ReqEn>0)&&($ReqEn<$deltaT) )
										{
											if ($BUCKETZ{$potatoes} < $ReqEn )
											{
												$BUCKETZ{$potatoes} = $ReqEn;
											}
										}
										else{}
									}
								}
							}
						}
						
						#if 	  MAT > DATSP
						if ( $MAT[$i] > $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i] ) 
						{
							my $ReqEn = ( $AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]  - $MAT[$i]   ); #how much energy is required to hit set point
							
							foreach my $potatoes (@{$lists})
							{
								if ($potatoes =~ m/HV/) #all heating is waste
								{
									if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
										&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $SimHC_Tempdb))	) 
									{
										if ($BUCKETZ{$potatoes} < ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]) )
										{
											$BUCKETZ{$potatoes} = ($AHU{ $AHUmap->getvta($potatoes) }[$i] - $AHU{ $AHUmap->getvtb($potatoes) }[$i]);
										}
									}
								}
									
								if ($potatoes =~ m/CCV/) 
								{
									if( looks_like_number($AHU{$potatoes}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($potatoes) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($potatoes) }[$i])
										&&($AHU{ $AHUmap->getvtb($potatoes) }[$i] > ($AHU{ $AHUmap->getvta($potatoes) }[$i] + $SimHC_Tempdb))	) 
									{
										my $deltaT = ( $AHU{ $AHUmap->getvtb($potatoes) }[$i] - $AHU{ $AHUmap->getvta($potatoes) }[$i] ); #temp change across the valve
										
										$ReqEn += $deltaT; #by adding deltaT to the required energy you are able to tell how much (if any) of the energy transfer across the valve is waste
										
										if ($ReqEn > $deltaT)
										{ 
											if ($BUCKETZ{$potatoes} < $deltaT )
											{
												$BUCKETZ{$potatoes} = $deltaT;
											} 
										}
										elsif ( ($ReqEn>0)&&($ReqEn<$deltaT) )
										{ 
											if ($BUCKETZ{$potatoes} < $ReqEn )
											{
												$BUCKETZ{$potatoes} = $ReqEn;
											} 
										}
										else{}
									}
								}
							}
						}
					}
				}
				#Empty dat Bucket!!!
				foreach my $PHV ($AHUmap->getPHV)
				{
					$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*$BUCKETZ{$PHV};
				}
				#Empty dat Bucket!!!
				foreach my $CCV ($AHUmap->getCCV)
				{
					$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*$BUCKETZ{$CCV};
				}
				#Empty dat Bucket!!!
				foreach my $RHV ($AHUmap->getRHV)
				{
					$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*$BUCKETZ{$RHV};
				}
				#aaaaaaw meh bucktz are empty :_(
			}
		}
		return %savings;
	}

	sub LeakyVlv #good to go!!
		#use this:	&LeakyVlv($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM))
	{
		my $i = $_[0];
		my $CFM = $_[1];
		
		my %savings =	(	
							'elec' => 0,
							'gas' => 0,
							'steam' => 0,
							'active' => 0
						);
		my %active = (
			"MAT" => ( looks_like_number($MAT[$i]) > 0),	#MAT
			"SCH" => ( looks_like_number($SCH[$i]) > 0),
			"SFS" => ( looks_like_number(&FanOn($i)) > 0),
			"CFM" => ( looks_like_number($CFM) > 0)
		);
		
		foreach my $key (keys %active)
		{
			unless ($active{$key})	#if any are false
			{
				return %savings;
			}
		}
		my @fatalPath;
		foreach my $lists ($AHUmap->getpaths)
		{
			my $sDAT = $AHUmap->getvta(${$lists}[-1]);
			my $sDATSP = $AHUmap->getvta(${$lists}[-1])."SP";
			$active{$sDAT} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1]) }[$i]) > 0);
			$active{$sDATSP} = (looks_like_number($AHU{ $AHUmap->getvta(${$lists}[-1])."SP" }[$i]) > 0); #DATSP
			unless($active{$sDAT}&&$active{$sDATSP})	#if you're missing either of DAT or DATSP
			{
				push @fatalPath, 1;	#if these are all fatal, then analytic is fatal, and returns 0
				next;	#no point of continuing after this.
			}
			my @fatalValve;
			foreach my $valve (@{$lists})
			{
				if($valve =~ m/D/) {next;}
				$active{$valve} = (looks_like_number($AHU{$valve}[$i]) > 0);
				$active{$AHUmap->getvta($valve)} = (looks_like_number($AHU{ $AHUmap->getvta($valve) }[$i]) > 0);
				$active{$AHUmap->getvtb($valve)} = (looks_like_number($AHU{ $AHUmap->getvtb($valve) }[$i]) > 0);
				unless( $active{$AHUmap->getvta($valve)}&&$active{$AHUmap->getvtb($valve)}&&$active{$valve} )	#if you are missing any one of tb or ta or valve signal
				{
					push @fatalValve, 1;	#if these are all fatal, then path is fatal
				}
				else
				{
					push @fatalValve, 0;
				}
			}
			my $fatalvFailure = 0;
			foreach my $fatal (@fatalValve)
			{
				$fatalvFailure += $fatal;
			}
			if($fatalvFailure == scalar(@fatalValve))	#only if all valves were fatal
			{
				push @fatalPath, 1;
			}
			else
			{
				push @fatalPath, 0;
			}
		}
		my $fatalpFailure = 0;
		foreach my $fatal (@fatalPath)
		{
			$fatalpFailure += $fatal;
		}
		
		if($fatalpFailure == scalar(@fatalPath))	#only if all paths were fatal
		{
			return %savings;
		}
		
		foreach my $key (keys(%active))
		{
			$savings{"active"} += $active{$key};
		}

		$savings{"active"} = $savings{"active"}/(scalar (keys(%active)));

		# print "I got called \n";
		
		# print @SCH;
		# print 
		
		
		if( @SCH&& ((scalar $AHUmap->getSF) > 0) )
		{
			if( ( looks_like_number($SCH[$i]) )&&( looks_like_number(&FanOn($i)) )&&(&FanOn($i))&&($SCH[$i])&&looks_like_number($CFM) )
			{	
				foreach my $PHV ($AHUmap->getPHV)
				{
					if( looks_like_number($AHU{$PHV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($PHV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($PHV) }[$i])
					&&($AHU{ $AHUmap->getvtb($PHV) }[$i] < ($AHU{ $AHUmap->getvta($PHV) }[$i]))&&($AHU{$PHV}[$i] < ( $AHUmap->getvmin($PHV) + $Leaky_Vlvdb))	) 
					{
						$savings{$AHUmap->getvenergy($PHV)} += $Konst*$CFM*($AHU{ $AHUmap->getvta($PHV) }[$i] - $AHU{ $AHUmap->getvtb($PHV) }[$i]);
					}
				}
				
				foreach my $CCV ($AHUmap->getCCV)
				{
					if( looks_like_number($AHU{$CCV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($CCV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($CCV) }[$i])
					&&($AHU{ $AHUmap->getvtb($CCV) }[$i] > ($AHU{ $AHUmap->getvta($CCV) }[$i]))&&($AHU{$CCV}[$i] < ($AHUmap->getvmin($CCV) + $Leaky_Vlvdb))	) 
					{
						$savings{$AHUmap->getvenergy($CCV)} += $Konst*$CFM*($AHU{ $AHUmap->getvtb($CCV) }[$i] - $AHU{ $AHUmap->getvta($CCV) }[$i]);
					}
				}

				foreach my $RHV ($AHUmap->getRHV)
				{
				
					if( looks_like_number($AHU{$RHV}[$i])&&looks_like_number($AHU{ $AHUmap->getvta($RHV) }[$i])&&looks_like_number($AHU{ $AHUmap->getvtb($RHV) }[$i])
					&&($AHU{ $AHUmap->getvtb($RHV) }[$i] < ($AHU{ $AHUmap->getvta($RHV) }[$i]))&&($AHU{$RHV}[$i] < ($AHUmap->getvmin($RHV) + $Leaky_Vlvdb))	) 
					{
						$savings{$AHUmap->getvenergy($RHV)} += $Konst*$CFM*($AHU{ $AHUmap->getvta($RHV) }[$i] - $AHU{ $AHUmap->getvtb($RHV) }[$i]);
					}
				}
			
			}
		}
		return %savings;
	}

	##^^Analytic Equations^^
		
	#VVTicket CalcsVV
	
	#make array of past months/years
	my @momonths = ($currentmonth,11,10,9,8,7,6,5,4,3,2,1); my @yearss = ($cyear,0,0,0,0,0,0,0,0,0,0,0); #will hold all months and years;
	for (my $mons = 0; $mons <= 10; $mons++)
	{
		my $tempthing = ($momonths[$mons]) - 1;
		if ($tempthing == 0)
		{
			$momonths[$mons+1] = 12;
			$yearss[$mons+1] = $cyear - 1;
		}
		else
		{
			$momonths[$mons+1] = $momonths[$mons] - 1;
			$yearss[$mons+1] = $yearss[$mons];
		}
	}
	#print @momonths, " is months\n";
	#print @yearss, " is years\n";
	
	
	foreach my $ticketLevel (keys %{${$ticket}{$sitename}{$AHUname}})	#this gets each ticket from the current $AHUname
	{
		$ticketsum += 1; #work order counter.
		#unless ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Return Status"} eq "Good Feedback") || ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Return Status"} eq "Bad Feedback Valid") ) { next; } 	#makes sure return status is gucci
		
		my $timeStart = &Timeround($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"StartTime"});
		my $timeEnd;
		if ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"EndTime"} =~ m/NULL/) {$timeEnd = "NULL"}
		else {$timeEnd = &Timeround($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"EndTime"});}
		print "------------------------\n";
		#print "\t\tTicketStart $timeStart\n\tTicketEnd $timeEnd\n\t\tData Start ${$AHU{TT}}[0]\n\tData End ${$AHU{TT}}[-1]";
		my $ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
		#print "\nTicket Index $ticketIndex\n\n";
		
		##########ticket outputs, new VVVVVVVVVVVV###############################################	
		
		#$ticketcounter{"Tickets per Asset...per Anomaly"}{$AHUname}{$hamburglar} += 1; #tickets per asset, per anomaly. NEEDED??????????
		my $AnnSum = 0;
		my $impday = 0;
		my $AnnSumi = 0;
		my $grimace = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"EndTime"}; #put endtime into a string for easy reading at the end
		my $ronald = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"StartTime"}; #put starttime into a string for easy reading at the end
		my $tstat = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Status"};
		
		##########################################################################################
			
		if ( !exists ($monthlyTicketCounts{$timeStart->format_cldr("MM yyyy")}) )
		{
			$monthlyTicketCounts{$timeStart->format_cldr("MM yyyy")} =
									{
										"Tickets" => 1,
										"CompletedCount" => 0,
										"OutstandingCount" => 0,
										"CompletedValue" => 0,
										"OutstandingValue" => 0,
									};
		}
		else {$monthlyTicketCounts{$timeStart->format_cldr("MM yyyy")}{"Tickets"}++;}
		#bobmarley is the activedays, add it to the ticket hash.
		if($timeEnd eq "NULL")
		{
			$bobmarley = timeIndex(${$AHU{"TT"}}[-1], $timeStart);
			$monthlyTicketCounts{$timeStart->format_cldr("MM yyyy")}{"OutstandingCount"}++;
		}
		else 
		{
			$bobmarley = timeIndex($timeEnd, $timeStart);
			$monthlyTicketCounts{$timeStart->format_cldr("MM yyyy")}{"CompletedCount"}++;
		}
		
		
		$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
		$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"TicketAge"} = &timeIndex(${$AHU{"TT"}}[-1], $timeStart)*(15/1440);
		
		my $anom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"}; #anomaly
		my $cause = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"}; #cause
		my $effect = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"}; #effect
				
		if ( $ticketIndex < 0 ) #ticket start time is before Data start time. Cannot Calculate. Report to DIAG
		{
			print "Ticket is before datastart. Bad.\n";
		}
		else	#ticket start time is after data start time. Good
		{
			print "After Start\n";
			
			if( $ticketIndex < scalar (@{$AHU{"TT"}}) )	#ticket start time before data end time. good.
			{
				print "Start time of ticket before endtime of data. Good.\n"; 
				if (($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"EndTime"} ne "NULL")&&( (timeIndex($timeEnd,${$AHU{"TT"}}[-1]) <= 0 ) ))  #if end time exists ANd it's within Databounds
				{
					print "endtoend:".timeIndex($timeEnd,${$AHU{"TT"}}[-1])."\n";
					print "Ticket End time before data end. Forreal.\n";
					if (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Below Set Point - Cooling/) 
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Cooling Capacity/) 
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature Less/ ) )  ) #if it is DATDEV Cooling event
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						print "fudge\n";
						my $translationHashRef = &sandwichSensorFudger();
						
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %active = activeCheckForDATDev($i);
							unless ( $active{"activePercentage"} ) {next;}
							my %datsave = &DATDevC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $active{"activePercentage"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						
						$impday = $annualize{$sitename}{"DATDevC"};
						print "impact days are $impday\n";
						$newAnom = "DAT Deviation";
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					#Marked for updating anomaly to be consistant.
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Below Set Point - Heating/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Heating Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature Less/ ) )  ) #if it is DATDEV Heating event, below set point. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DAT Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Above Set Point - Cooling/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Cooling Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature Greater/ ) )  ) #if it is DATDEV Cooling event, above set point. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DAT Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DSP Below Set Point/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU VFD Control/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Duct Static Pressure Less/ ) )  ) #if it is DSPDev Below event. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DSP Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					
					
					
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Above Set Point - Heating/)
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Heating Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature/ ) )  ) #if it is DATDEV Heating event
					{
						
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						
						my $translationHashRef = &sandwichSensorFudger();
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %active = activeCheckForDATDev($i);
							unless ( $active{"activePercentage"} ) {next;}
							my %datsave = &DATDevH($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};		
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $active{"activePercentage"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						$impday = $annualize{$sitename}{"DATDevH"};
						print "impact days are $impday\n";
						$newAnom = "DAT Deviation";
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Overage Running Hours/)
					|| ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Out of Occupancy/) ) #if it is Overage Running Hours or Out of Occupancy
					{
						print $ooo $AHUname."\n";
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						my $translationHashRef = &sandwichSensorFudger();
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %active = activeCheckForOutOfOcc($i);
							unless ( $active{"activePercentage"} ) {next;}
							
							my %datsave = &OutofOcc($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM), &REALLYMakeVFD($i, $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $active{"activePercentage"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						
						$impday = $annualize{$sitename}{"OutofOcc"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Leaky Damper/) ) #if it is Overage Running Hours or Out of Occupancy
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal
						my $translationHashRef = &sandwichSensorFudger();
						
						###Weekly Treatment Code###
						$timeStart->subtract(days => 7);
						$timeStart = Timeround($timeStart);
						$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
						$bobmarley = timeIndex($timeEnd, $timeStart);
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
						###Weekly Treatment Code###
						
						#print "|";
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &LeakyDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						$impday = $annualize{$sitename}{"LeakyDamp"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Stuck Damper/) ) #if it is Overage Running Hours or Out of Occupancy
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						my $translationHashRef = &sandwichSensorFudger();
						###Weekly Treatment Code###
						$timeStart->subtract(days => 7);
						$timeStart = Timeround($timeStart);
						$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
						$bobmarley = timeIndex($timeEnd, $timeStart);
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
						###Weekly Treatment Code###
						
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							my %datsave = &StuckDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						
						$impday = $annualize{$sitename}{"StuckDamp"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DSP Above Set Point/) #Duct Static Pressure Deviation?
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU VFD Control/) 
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Duct Static Pressure Greater/ ) )  ) #if it is Overage Running Hours or Out of Occupancy
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						print $dbg "VDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSPDSP\nV";

						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{

							my %datsave = &DSPDev($i, &REALLYMakeVFD($i, $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						$impday = $annualize{$sitename}{"DSPDev"};
						print "impact days are $impday\n";
						$newAnom = "DSP Deviation";
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Simultaneous Heat/) ) #
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.

						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &SimHC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						print "Gas savings in kWh is ";
						print $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"};
						print "\n";
						$impday = $annualize{$sitename}{"SimHC"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Leaky Valve/) ) #
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = 0;		#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = 0;	#forreal.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						###Weekly Treatment Code###
						$timeStart->subtract(days => 7);
						$timeStart = Timeround($timeStart);
						$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
						$bobmarley = timeIndex($timeEnd, $timeStart);
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
						###Weekly Treatment Code###
						
						for(my $i = $ticketIndex; $i <= timeIndex ($timeEnd, $AHU{"TT"}[0]); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							
							my %datsave = &LeakyVlv($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM),), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						$impday = $annualize{$sitename}{"LeakyVlv"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};
					}
					
					if(exists $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"})
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"} = $ConvElec*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"} = $ConvGas*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"} = $ConvSteam*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"};
					
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec_dollar"} = $DollarElec*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas_dollar"} = $DollarGas*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam_dollar"} = $DollarSteam*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"};
						
						print ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"}, " ");
						
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"ImpactDays"} = $impday;

						#take each individual wastes
						
						#equation is (waste/activedays)*impactdays
						#put annualized savings into the hashes
						if ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} == 0) #no active time stamps.
						{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"} = 0; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"} = 0; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"} = 0; #gas
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"} = 0; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"} = 0; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"} = 0; #gas
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = 0;
						}
						else 
						{
							$bobmarley = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"}/96;
							my $lilpony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec"};
							my $liltony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam"};
							my $lilrony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas"};
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"} = ($lilpony/$bobmarley)*$impday; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"} = ($liltony/$bobmarley)*$impday; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"} = ($lilrony/$bobmarley)*$impday; #gas
							
							$lilpony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings elec_dollar"};
							$liltony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings steam_dollar"};
							$lilrony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Realized Savings gas_dollar"};
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"} = ($lilpony/$bobmarley)*$impday; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"} = ($liltony/$bobmarley)*$impday; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"} = ($lilrony/$bobmarley)*$impday; #gas

							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"}/$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"};
							if ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} > 1){ $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = 1; }
							
						}

						#add up this ticket's annualized sum.
						$AnnSum = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
						$AnnSumi = $AnnSum;
						if($AnnSum > 0)	#if the ticket is non-zero
						{
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"TicketAge"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"TicketAge"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnSum"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnSumb"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnkWh"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"Anngas"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"Annsteam"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"impday"} = $impday;
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"timeStart"} = $timeStart;
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"timeEnd"} = $timeEnd;
						}
						$AnnkWh += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"};
						$Anngas += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"};
						$Annsteam += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"};
					
						#Total W.O.
						$ticketcount+= 1; #will have total number of tickets
						#Algorithm 
						#WORKS
						
						if(exists($alg{$newAnom}))
						{
							$alg{$newAnom}{"Tickets"} += 1; #tickets per anomaly
						}
						else #must initialize values! or else you're adding 1 to undef...
						{
							$alg{$newAnom}{"Tickets"} = 1; #tickets per anomaly
							$alg{$newAnom}{"OutstandingValue"} = 0; #value per analytic
							$alg{$newAnom}{"CompletedValue"} = 0; #value per analytic
						}
						#AHU
						if( exists($ahuhash{$AHUname}) )
						{
							$ahuhash{$AHUname}{"Tickets"} += 1; #tickets per asset
						}
						else 
						{
							$ahuhash{$AHUname}{"Tickets"} = 1; #tickets per anomaly
							$ahuhash{$AHUname}{"OutstandingValue"} = 0; #value per analytic
							$ahuhash{$AHUname}{"CompletedValue"} = 0; #value per analytic
						}
						#Equipment
						#big if statement to read (anomaly || (cause && effect) ) and assigns an equipment type. first if statement for AHU. Others for future equipment to be included. Not sure how to figure this out any other way right now.
						#WORKS
						if ($anom =~ m/DAT/ || $anom =~ m/Leaky/ || $anom =~ m/Stuck/ || $anom =~ m/DSP/ || $anom =~ m/Overage Running Hours/ || $anom =~ m/Out of Occupancy/ 
						|| $anom =~ m/Simultaneous/ || $anom =~ m/AHU/ || $cause =~ m/AHU/ || (($cause =~ m/AHU Cooling/ || $cause =~ m/AHU Heating/) && ($effect =~ m/Supply Air/ || $effect =~ m/Discharge Air/)) 
						|| ($cause =~ m/AHU VFD/ && $effect =~ m/Duct Static Pressure/))
						{
							$equip{"Air Handler (All)"}{"Tickets"} += 1; #ticket count
						}
						else
						{
							$equip{"Other Equipment"}{"Tickets"} += 1;
						}
						$AnnSumo += $AnnSum;
						print "${$ticket}{$sitename}{$AHUname}{$ticketLevel} savings is $AnnSum\n";
						
					}
					else #for tickets with no quantifying savings
					{
						if(exists($alg{$anom}))
						{
							$alg{$anom}{"Tickets"} += 1; #tickets per anomaly
						}
						else #must initialize values! or else you're adding 1 to undef...
						{
							$alg{$anom}{"Tickets"} = 1; #tickets per anomaly
							$alg{$anom}{"OutstandingValue"} = 0; #value per analytic
							$alg{$anom}{"CompletedValue"} = 0; #value per analytic
						}
						if( exists($ahuhash{$AHUname}) )
						{
							$ahuhash{$AHUname}{"Tickets"} += 1; #tickets per asset
						}
						else 
						{
							$ahuhash{$AHUname}{"Tickets"} = 1; #tickets per anomaly
							$ahuhash{$AHUname}{"OutstandingValue"} = 0; #value per analytic
							$ahuhash{$AHUname}{"CompletedValue"} = 0; #value per analytic
						}
						$equip{"Air Handler (All)"}{"Tickets"} += 1; #ticket count
						$equip{"Air Handler (All)"}{"Value"} += 0; #tickets' value $$$$$
					}
				}
				
				else #ticket end time after data end time, or it doesn't exist. 
				{
					$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"EndTime"} = "NULL"; 	#this deletes the ticket endtime if it existed, but it was out of bounds. 
																						#This is good, since it fudges the fact that we decided to get the ticket lists late, lol
					print "Ticket End time \"doesn't\" exist. Potential.\n";
					if (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Below Set Point - Cooling/) 
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Cooling Capacity/) 
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature/ ) )  ) #if it is DATDEV Cooling event
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						my $translationHashRef = &sandwichSensorFudger();
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %active = activeCheckForDATDev($i);
							unless ( $active{"activePercentage"} ) {next;}
							my %datsave = &DATDevC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $active{"activePercentage"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						$impday = $annualize{$sitename}{"DATDevC"};
						print "impact days are $impday\n";
						$newAnom = "DAT Deviation";
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
						 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Above Set Point - Heating/)
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Heating Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature/ ) )  ) #if it is DATDEV Heating event
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &DATDevH($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						$impday = $annualize{$sitename}{"DATDevH"};
						print "impact days are $impday\n";
						$newAnom = "DAT Deviation"; 
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Below Set Point - Heating/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Heating Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature Less/ ) )  ) #if it is DATDEV Heating event, below set point. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DAT Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DAT Above Set Point - Cooling/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU Cooling Capacity/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Supply Air Temperature Greater/ ) )  ) #if it is DATDEV Cooling event, above set point. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DAT Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DSP Below Set Point/)
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU VFD Control/)
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Duct Static Pressure Less/ ) )  ) #if it is DSPDev Below event. Cannot calculate savings and such, assign new anomaly.
					{
						$newAnom = "DSP Deviation";
						$anom = $newAnom;
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Overage Running Hours/)
					|| ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Out of Occupancy/) ) #if it is Overage Running Hours or Out of Occupancy
					{
						print $ooo $AHUname."\n";
						
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						my $translationHashRef = &sandwichSensorFudger();
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							my %active = activeCheckForOutOfOcc($i);
							unless ( $active{"activePercentage"} ) {next;}
							
							my %datsave = &OutofOcc($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM), &REALLYMakeVFD($i, $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $active{"activePercentage"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						$impday = $annualize{$sitename}{"OutofOcc"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"}; 

						 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Leaky Damper/) ) #Leaky Damper
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						my $translationHashRef = &sandwichSensorFudger();
							
						###Weekly Treatment Code###
						$timeStart->subtract(days => 7);
						$timeStart = Timeround($timeStart);
						$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
						$bobmarley = timeIndex(${$AHU{"TT"}}[-1], $timeStart);
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
						###Weekly Treatment Code###
							
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &LeakyDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						
						$impday = $annualize{$sitename}{"LeakyDamp"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"}; 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Stuck Damper/) ) #Stuck Damper
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						
						my $translationHashRef = &sandwichSensorFudger();
						
						###Weekly Treatment Code###
						$timeStart->subtract(days => 7);
						$timeStart = Timeround($timeStart);
						$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
						$bobmarley = timeIndex(${$AHU{"TT"}}[-1], $timeStart);
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
						###Weekly Treatment Code###
						
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &StuckDamper($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						&sandwichSensorUnfudger($translationHashRef);
						
						$impday = $annualize{$sitename}{"StuckDamp"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"}; 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/DSP Above Set Point/) #Duct Static Pressure Deviation?
					
					|| ( ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Cause"} =~ m/AHU VFD Control/) 
					&& ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Effect"} =~ m/Duct Static Pressure Greater/ ) )  ) #if it is Overage Running Hours or Out of Occupancy
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &DSPDev($i, &REALLYMakeVFD($i, $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						$impday = $annualize{$sitename}{"DSPDev"};
						print "impact days are $impday\n";
						$newAnom = "DSP Deviation"; 
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} = $newAnom;

						 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Simultaneous Heat/) ) #
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &SimHC($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM)), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}

						$impday = $annualize{$sitename}{"SimHC"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"};  
						 
					}
					elsif (  ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"} =~ m/Leaky Valve/) ) #
					{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = 0;		#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = 0;	#fofake.
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} = 0;	#forreal.
							
							###Weekly Treatment Code###
							$timeStart->subtract(days => 7);
							$timeStart = Timeround($timeStart);
							$ticketIndex = timeIndex ($timeStart, ${$AHU{"TT"}}[0]);
							$bobmarley = timeIndex(${$AHU{"TT"}}[-1], $timeStart);
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"} = $bobmarley + 1;
							###Weekly Treatment Code###
						#print "|";
						for(my $i = $ticketIndex; (($i < scalar (@{$AHU{"TT"}}))&&($i < scalar (@OAT))); $i++) #basically do while $i is NOT greater than the position $timeEnd is in, relative to the first timestamp of the AHU data
						{
							#print $AHU{"TT"}[$i]."|";
							my %datsave = &LeakyVlv($i, &MakeCFM($i, MakeVFD($i,REALLYMakeVFD($i, $MaxCFM),), $MaxCFM));
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} += $datsave{"elec"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} += $datsave{"gas"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} += $datsave{"steam"};
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} += $datsave{"active"};
						}
						$impday = $annualize{$sitename}{"LeakyVlv"};
						print "impact days are $impday\n";
						$newAnom = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Anomaly"}; 
					}
					if(exists $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"})
					{
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"} = $ConvElec*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"} = $ConvGas*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"} = $ConvSteam*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"};
						
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec_dollar"} = $DollarElec*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas_dollar"} = $DollarGas*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"};
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam_dollar"} = $DollarSteam*$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"};
						
						$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"ImpactDays"} = $impday;
						
						
						
						if ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"} == 0) #no active time stamps.
						{
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"} = 0; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"} = 0; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"} = 0; #gas
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"} = 0; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"} = 0; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"} = 0; #gas
							
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = 0;
						}
						else 
						{
							$bobmarley = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"}/96;
							
							my $lilpony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec"};
							my $liltony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam"};
							my $lilrony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas"};
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"} = ($lilpony/$bobmarley)*$impday; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"} = ($liltony/$bobmarley)*$impday; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"} = ($lilrony/$bobmarley)*$impday; #gas
							
							$lilpony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings elec_dollar"};
							$liltony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings steam_dollar"};
							$lilrony = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Potential Savings gas_dollar"};
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"} = ($lilpony/$bobmarley)*$impday; #elec annualized savings
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"} = ($liltony/$bobmarley)*$impday; #steam
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"} = ($lilrony/$bobmarley)*$impday; #gas
							
							
							
							$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"CalcActive"}/$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"RealActiveStamps"};
							if ($ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} > 1){ $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Data Reliability"} = 1; }	
						}
						
						
						$AnnSum = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
						$AnnSumi = $AnnSum;
						if($AnnSum > 0)	#if the ticket is non-zero
						{
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"TicketAge"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"TicketAge"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnSum"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnSumb"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings_dollar"}+$ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings_dollar"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"AnnkWh"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"Anngas"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"Annsteam"} = $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"};
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"impday"} = $impday;
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"timeStart"} = $timeStart;
							$latestAnnul{$AHUname}{$newAnom}{$ticketLevel}{"timeEnd"} = $timeEnd;
						}
						$AnnkWh += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized elec savings"};
						$Anngas += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized gas savings"};
						$Annsteam += $ticket->{$sitename}->{$AHUname}->{$ticketLevel}->{"Annualized steam savings"};
						#Total W.O.
						$ticketcount += 1; #will have total number of tickets
						#Algorithm
						#works
						if(exists($alg{$newAnom}))
						{
							$alg{$newAnom}{"Tickets"} += 1; #tickets per anomaly
						}
						else #must initialize values! or else you're adding 1 to undef...
						{
							$alg{$newAnom}{"Tickets"} = 1; #tickets per anomaly
							$alg{$newAnom}{"OutstandingValue"} = 0; #value per analytic
							$alg{$newAnom}{"CompletedValue"} = 0; #value per analytic
						}
						#AHU
						if( exists($ahuhash{$AHUname}) )
						{
							$ahuhash{$AHUname}{"Tickets"} += 1; #tickets per asset
						}
						else 
						{
							$ahuhash{$AHUname}{"Tickets"} = 1; #tickets per anomaly
							$ahuhash{$AHUname}{"OutstandingValue"} = 0; #value per analytic
							$ahuhash{$AHUname}{"CompletedValue"} = 0; #value per analytic
						}
					
						#Equipment
						#big if statement to read (anomaly || (cause && effect) ) and assigns an equipment type. first if statement for AHU. Others for future equipment to be included. Not sure how to figure this out any other way right now.
						if ($anom =~ m/DAT/ || $anom =~ m/Leaky/ || $anom =~ m/Stuck/ || $anom =~ m/DSP/ || $anom =~ m/Overage Running Hours/ || $anom =~ m/Out of Occupancy/ 
						|| $anom =~ m/Simultaneous/ || $anom =~ m/AHU/ || $cause =~ m/AHU/ || (($cause =~ m/AHU Cooling/ || $cause =~ m/AHU Heating/) && ($effect =~ m/Supply Air/ || $effect =~ m/Discharge Air/)) 
						|| ($cause =~ m/AHU VFD/ && $effect =~ m/Duct Static Pressure/))
						{
							$equip{"Air Handler (All)"}{"Tickets"} += 1; #ticket count
						}
						else
						{
							$equip{"Other Equipment"}{"Tickets"} += 1;
						}
						$AnnSumo += $AnnSum;
						print "${$ticket}{$sitename}{$AHUname}{$ticketLevel} savings is $AnnSum\n";
						##################################################################################
						##################################################################################
					}
					else #for tickets with no quantifying savings
					{
						if(exists($alg{$anom}))
						{
							$alg{$anom}{"Tickets"} += 1; #tickets per anomaly
						}
						else #must initialize values! or else you're adding 1 to undef...
						{
							$alg{$anom}{"Tickets"} = 1; #tickets per anomaly
							$alg{$anom}{"OutstandingValue"} = 0; #value per analytic
							$alg{$anom}{"CompletedValue"} = 0; #value per analytic
						}
						if( exists($ahuhash{$AHUname}) )
						{
							$ahuhash{$AHUname}{"Tickets"} += 1; #tickets per asset
						}
						else 
						{
							$ahuhash{$AHUname}{"Tickets"} = 1; #tickets per anomaly
							$ahuhash{$AHUname}{"OutstandingValue"} = 0; #value per analytic
							$ahuhash{$AHUname}{"CompletedValue"} = 0; #value per analytic
						}
						$equip{"Air Handler (All)"}{"Tickets"} += 1; #ticket count
						$equip{"Air Handler (All)"}{"Value"} += 0; #tickets' value $$$$$
					}
				}
			}
			else	#ticket start time after data end time
			{
				print "Ticket is after dataend. Bad.\n\t TI:$ticketIndex\n\tTicket:$timeEnd\n\tData:${$AHU{TT}}[-1]\n\n";
				next;
			}
			print $AnnSum;
		}	
	}
	
	#####################print everything out for ReportData.csv###
	open (my $RepDat1, '>', 'ReportData_save.csv');
	
	 $AnnSumo = 0;
	 $AnnkWh = 0;
	 $Anngas = 0;
	 $Annsteam = 0;
	
	########DENNIS 666##########
	########DENNIS 666##########
	########DENNIS 666##########
	########DENNIS 666##########
	#zeroing all cumulative variables because fuck shit
	foreach my $whythefuckisthiseveryloop (keys %alg)
	{
		$alg{$whythefuckisthiseveryloop}{"OutstandingValue"} = 0; #value per analytic
		$alg{$whythefuckisthiseveryloop}{"CompletedValue"} = 0; #value per analytic
	}
	foreach my $whythefuckisthiseveryloop (keys %ahuhash)
	{
		$ahuhash{$whythefuckisthiseveryloop}{"OutstandingValue"} = 0;
		$ahuhash{$whythefuckisthiseveryloop}{"CompletedValue"} = 0;
	}
	$equip{"Air Handler (All)"}{"Value"} = 0;
	foreach my $whythefuckisthiseveryloop (keys %monthlyTicketCounts)
	{
		$monthlyTicketCounts{$whythefuckisthiseveryloop}{"CompletedValue"} = 0;
		$monthlyTicketCounts{$whythefuckisthiseveryloop}{"OutstandingValue"} = 0;
	}
	
	foreach my $AHUnamean (keys %latestAnnul)
	{
		print "AHUnamean is $AHUnamean \n";
		foreach my $annaMolly (keys %{$latestAnnul{$AHUnamean}})
		{
			my $prevDeath = "NULL";
			foreach my $TickID (sort { $latestAnnul{$AHUnamean}{$annaMolly}{$b}{"TicketAge"} <=> $latestAnnul{$AHUnamean}{$annaMolly}{$a}{"TicketAge"} } keys %{$latestAnnul{$AHUnamean}{$annaMolly}})
			{
				my $currDeath = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"TicketAge"} - $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"impday"};
				print "currDeath is $currDeath \n";
				if((looks_like_number($prevDeath))&&(($prevDeath - $currDeath )> $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"impday"})) { $prevDeath = "NULL"; }
				print "$TickID\t".$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"TicketAge"}."\n";
				if($prevDeath eq "NULL")
				{
					$AnnSumo += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnSum"};	#prioritizes oldest ticket in annuls
					$AnnkWh += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnkWh"};
					$Anngas += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Anngas"};
					$Annsteam += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Annsteam"};
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnSum"};
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truegas"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Anngas"};
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truekWh"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnkWh"};
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truesteam"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Annsteam"};
					
					$equip{"Air Handler (All)"}{"Value"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
					
					if($latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeEnd"} eq "NULL")
					{
						$monthlyTicketCounts{$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeStart"}->format_cldr("MM yyyy")}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$alg{$annaMolly}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$ahuhash{$AHUnamean}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						print "should be outstanding\n";
						print $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						
					}
					else
					{
						$monthlyTicketCounts{$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeStart"}->format_cldr("MM yyyy")}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$ahuhash{$AHUnamean}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$alg{$annaMolly}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						print "in here!\n";
					}
				}
				elsif($prevDeath < 0) {last;} #If it dies after the month, these tickets won't apply
				else
				{
					my $annulFraction = ($currDeath - $prevDeath)/($currDeath - $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"TicketAge"});	#this is the fraction in which this ticket applies to annualization
					print "annulFraction is $annulFraction \n";
					$AnnSumo += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnSum"}*$annulFraction;
					$AnnkWh += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnkWh"}*$annulFraction;
					$Anngas += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Anngas"}*$annulFraction;
					$Annsteam += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Annsteam"}*$annulFraction;
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnSum"}*$annulFraction;
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truegas"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Anngas"}*$annulFraction;
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truesteam"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"Annsteam"}*$annulFraction;
					$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"truekWh"} = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"AnnkWh"}*$annulFraction;
					
					$equip{"Air Handler (All)"}{"Value"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
					
					if($latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeEnd"} eq "NULL")
					{
						$monthlyTicketCounts{$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeStart"}->format_cldr("MM yyyy")}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$alg{$annaMolly}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$ahuhash{$AHUnamean}{"OutstandingValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						print "should be outstanding\n";
						print $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
					}
					else
					{
						$monthlyTicketCounts{$latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"timeStart"}->format_cldr("MM yyyy")}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$ahuhash{$AHUnamean}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						$alg{$annaMolly}{"CompletedValue"} += $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
						print "in here!\n";
					}
					print $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"trueAnnul"};
				}
				$prevDeath = $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"TicketAge"} - $latestAnnul{$AHUnamean}{$annaMolly}{$TickID}{"impday"};
				print "PrevDeath is $prevDeath \n";
			}
		}
	}
	$cmc = 0; $cmo = 0; $cmcsave = 0; $cmosave = 0;
	$pmc = 0; $pmo = 0; $pmcsave = 0; $pmosave = 0; 
	$lifec = 0; $lifeo = 0; $lifecsave = 0; $lifeosave = 0;
	
	foreach my $monthspaceyear (keys %monthlyTicketCounts)
	{
		if($monthspaceyear eq "0$currentmonth $cyear") #Joe temporary fix, def wont work for tickets for currentmonth = OCT, NOV, DEC
        {
            $cmc += $monthlyTicketCounts{$monthspaceyear}{"CompletedCount"}; $cmo += $monthlyTicketCounts{$monthspaceyear}{"OutstandingCount"}; 
            $cmcsave += $monthlyTicketCounts{$monthspaceyear}{"CompletedValue"}; $cmosave += $monthlyTicketCounts{$monthspaceyear}{"OutstandingValue"};
            $lifec += $monthlyTicketCounts{$monthspaceyear}{"CompletedCount"}; $lifeo += $monthlyTicketCounts{$monthspaceyear}{"OutstandingCount"}; 
            $lifecsave += $monthlyTicketCounts{$monthspaceyear}{"CompletedValue"};  $lifeosave += $monthlyTicketCounts{$monthspaceyear}{"OutstandingValue"}; 
            print "made it in!";
        }
		else
		{
			$pmc += $monthlyTicketCounts{$monthspaceyear}{"CompletedCount"}; $pmo += $monthlyTicketCounts{$monthspaceyear}{"OutstandingCount"};  
			$pmcsave += $monthlyTicketCounts{$monthspaceyear}{"CompletedValue"}; $pmosave += $monthlyTicketCounts{$monthspaceyear}{"OutstandingValue"};
			$lifec += $monthlyTicketCounts{$monthspaceyear}{"CompletedCount"}; $lifeo += $monthlyTicketCounts{$monthspaceyear}{"OutstandingCount"}; 
			$lifecsave += $monthlyTicketCounts{$monthspaceyear}{"CompletedValue"}; $lifeosave += $monthlyTicketCounts{$monthspaceyear}{"OutstandingValue"};
		}
	}
		my $mocount = scalar keys %mhash;
	if ($mocount < 12) #if less than 12 months in the hash, add extra months, with 0 for ticket counts
	{
		for (my $x=1; $x<=12; $x++)
		{
			if(exists($mhash{"$x"}))
			{
				print "this month exists: $x \n";
			}
			else
			{
				$mhash{"$x"}{"Completed"} = 0;
				$mhash{"$x"}{"Outstanding"} = 0;
			}
		}
	}
	else #site is >= 1 year old
	{
	}
	print Dumper \%mhash;

	#######################printing TreeMapData outputs into .csv#########################################
	#WORKS
	open (my $TreeEquip, '>', 'TreeEquip.csv');
	open (my $TreeAHU, '>', 'TreeAHU.csv');
	open (my $TreeAlg, '>', 'TreeAlg.csv');
	my $count1 = scalar keys %equip;
	my $count2 = scalar keys %ahuhash;
	my $count3 = scalar keys %alg;
	
	for (my $x=1; $x<=$count1+1; $x++)
	{	
		if ($x==1)
		{
			print $TreeEquip ("equipment,", "equipment.tickets,",	"equipment.value,");
			print $TreeEquip "\n"; #go to next line
		}
	
		if ($x==2)
		{
			foreach my $level (keys(%equip))
			{
				print $TreeEquip ($level,",");
				print $TreeEquip ($equip{$level}{'Tickets'},",");
				print $TreeEquip ($equip{$level}{'Value'},",");
				print $TreeEquip "\n";
			}
		}
	}
	for (my $x=1; $x<=$count2+1; $x++)
	{	
		if ($x==1)
		{
			print $TreeAHU ("airside.equipment,",	"airside.equipment.tickets,",	"airside.equipment.value,");
			print $TreeAHU "\n"; #go to next line
		}
	
		if ($x==2)
		{
			foreach my $level (keys(%ahuhash))
			{
				print $TreeAHU ($level,",");
				print $TreeAHU ($ahuhash{$level}{'Tickets'},",");
				print $TreeAHU ($ahuhash{$level}{'OutstandingValue'}+$ahuhash{$level}{'CompletedValue'},",");
				print $TreeAHU "\n";
			}
		}
	}
	for (my $x=1; $x<=$count3+1; $x++)
	{	
		if ($x==1)
		{
			print $TreeAlg "algorithm,"."algorithm.tickets,"."algorithm.value,";
			print $TreeAlg "\n"; #go to next line
		}
	
		if ($x==2)
		{
			foreach my $level (keys(%alg))
			{
				print $TreeAlg ($level,",");
				print $TreeAlg ($alg{$level}{'Tickets'},",");
				print $TreeAlg ($alg{$level}{'OutstandingValue'}+$alg{$level}{'CompletedValue'},",");
				print $TreeAlg "\n";
			}
		}
	}
	close($TreeEquip);
	close($TreeAHU);
	close($TreeAlg);
	
	#########################################################################################
	########################Three separate files for TreeMapData.csv to be made##############
	#########################################################################################
	###########Need to find top 8 algorithms and assets by # of tickets or value, they are already divided by completed/outstandings ######################################
	
	
	#Top 8 Assets (later do same for anomalies)
	#WORKS
	my %ahuvalue; #directly store "AHU# => value"
	foreach my $wi (keys %ahuhash) #Will create a new, single level hash where each key will be the AHU, and its value will literally be the value (avoidance cost)
	{
		$ahuvalue{$wi} = $ahuhash{$wi}{"CompletedValue"} + $ahuhash{$wi}{"OutstandingValue"};
	}		
	print Dumper \%ahuvalue;
	my @ahurow; #array will store top 8 AHUs in order, for reference later (dont need TOTAL avoidable cost, need completed vs outstanding)
	my $nums = 0;
	foreach my $name (sort { $ahuvalue{$b} <=> $ahuvalue{$a} } keys %ahuvalue) #sort by highest->lowest
	{
		if ($nums <=7) #only add up to top 8 assets
		{
			$ahurow[$nums] = $name;
			$nums++;
		}
		else
		{
		}
	}
	my $ahucount = scalar @ahurow;
	#print @ahurow, "\n"; #order of most valuable ahu avoidance;
	#do a search through all %ahuhash ahus in %ticket, using the @ahurow. accumulate realized avoidance and potential separately.
	my %hashahu; #keep track of and store top 8 ahu's value in terms of Completed and Outstanding, separated.
	my $assetahu; #will be the asset, from the top 8.
	for (my $y=1; $y<=$ahucount; $y++) #loop up to 8 times, depending on number of assets!
	{	
		my $Cann = 0; #completed annualized
		my $Oann = 0; #outstanding annualized
		$assetahu = $ahurow[$y-1]; #the current "top" asset
		$hashahu{$assetahu}{"Completed"} = $ahuhash{$assetahu}{"CompletedValue"};
		$hashahu{$assetahu}{"Outstanding"} = $ahuhash{$assetahu}{"OutstandingValue"};
	}
	print Dumper \%hashahu; #new hash with top 8 assets.
	
	#TOP 8 ALGORITHMS!
	#DOES NOT WORK, JOE
	my %algvalue; #directly store "AnomalyType => Value"
	foreach my $wi (keys %alg) #Will create a new, single level hash where each key will be the alg/anomaly, and its value will literally be the value (avoidance cost)
	{
		$algvalue{$wi} = $alg{$wi}{"CompletedValue"} - $alg{$wi}{"OutstandingValue"};
	}		
	print Dumper \%algvalue;
	my @algrow; #array will store top 8 Anomalies in order, for reference later (dont need TOTAL avoidable cost, need completed vs outstanding)
	my $numso = 0;
	foreach my $name (sort { $algvalue{$b} <=> $algvalue{$a} } keys %algvalue) #sort by highest->lowest
	{
		if ($numso <=7) #only add up to top 8 assets
		{
			$algrow[$numso] = $name;
			$numso++;
		}
		else
		{
		}
	}
	my $algcount = scalar @algrow;
	#print @algrow, "\n"; #order of most valuable algorithm avoidance, highest->lowest;
	#do a search through all %alg algs in %ticket, using the @ahurow. accumulate realized avoidance and potential separately.
	#my %hashalg; #keep track of and store top 8 ahu's value in terms of Completed and Outstanding, separated.
	#my $algalg; #will be the asset, from the top 8.
	for (my $y=1; $y<=$algcount; $y++) #loop up to 8 times, depending on number of anomalies!
	{
		$Calg = 0; #completed annualized initialize
		$Oalg = 0; #outstanding annualized initialize
		$algalg = $algrow[$y-1]; #the current "top" algorithm
		
		$hashalg{$algalg}{"Completed"} = $alg{$algalg}{"CompletedValue"};
		$hashalg{$algalg}{"Outstanding"} = $alg{$algalg}{"OutstandingValue"};
	}
	
	
	print Dumper \%hashalg; #new hash with top 8 algorithms.
	
	print $RepDat1 ("Work Order Quantity,", $ticketsum, "\n");
	print $RepDat1 ("Annual Avoidable Cost,",$AnnSumo,"\n");
	print $RepDat1 ("Energy (kWh),",$AnnkWh,"\n");
	print $RepDat1 ("Energy (gas),",$Anngas,"\n");
	print $RepDat1 ("Energy (steam),",$Annsteam,"\n");
	print $RepDat1 ("Carbon Dioxide (metric tons),",,"\n");
	print $RepDat1 ("Current Month Completed Work Orders Quantity,",$cmc,"\n");
	print $RepDat1 ("Current Month Outstanding Work Orders Quantity,",$cmo,"\n");
	print $RepDat1 ("Current Month Completed Work Orders Value,",$cmcsave,"\n");
	print $RepDat1 ("Current Month Outstanding Work Orders Value,",$cmosave,"\n");
	print $RepDat1 ("Carryover Month Completed Work Orders Quantity,",$pmc,"\n");
	print $RepDat1 ("Carryover Month Outstanding Work Orders Quantity,",$pmo,"\n");
	print $RepDat1 ("Carryover Month Completed Work Orders Value,",$pmcsave,"\n");
	print $RepDat1 ("Carryover Month Outstanding Work Orders Value,",$pmosave,"\n");
	print $RepDat1 ("Lifetime Month Completed Work Orders Quantity,",$lifec,"\n");
	print $RepDat1 ("Lifetime Month Outstanding Work Orders Quantity,",$lifeo,"\n");
	print $RepDat1 ("Lifetime Month Completed Work Orders Value,",$lifecsave,"\n");
	print $RepDat1 ("Lifetime Month Outstanding Work Orders Value,",$lifeosave,"\n");
	print $RepDat1 ("Series Name,Completed,Outstanding\n");
	#fun stuff, maybe
	for (my $x= 11; $x>=0; $x--) #loop through 12 times, each for 1 month in the last year, in order starting from 1 year ago.
	{
		my $mo = $momonths[$x]; #first month (last element of @momonths)
		my $ye = $yearss[$x]; #corresponding year
		my $mcomp = 0;
		if ( exists ($monthlyTicketCounts{"$mo $ye"}) ){ $mcomp = $monthlyTicketCounts{"$mo $ye"}{"CompletedCount"}; }
		if ( exists ($monthlyTicketCounts{"0$mo $ye"}) ){ $mcomp = $monthlyTicketCounts{"0$mo $ye"}{"CompletedCount"}; }
		my $mout = 0;
		if ( exists ($monthlyTicketCounts{"$mo $ye"}) ){ $mout = $monthlyTicketCounts{"$mo $ye"}{"OutstandingCount"}; }
		if ( exists ($monthlyTicketCounts{"0$mo $ye"}) ){ $mout = $monthlyTicketCounts{"0$mo $ye"}{"OutstandingCount"}; }
		
		if ($mo == 1)
		{
			print $RepDat1 ("January $ye,$mcomp,$mout");
		}
		if ($mo == 2)
		{
			print $RepDat1 ("February $ye,$mcomp,$mout");
		}
		if ($mo == 3)
		{
			print $RepDat1 ("March $ye,$mcomp,$mout");
		}
		if ($mo == 4)
		{
			print $RepDat1 ("April $ye,$mcomp,$mout");
		}
		if ($mo == 5)
		{
			print $RepDat1 ("May $ye,$mcomp,$mout");
		}
		if ($mo == 6)
		{
			print $RepDat1 ("June $ye,$mcomp,$mout");
		}
		if ($mo == 7)
		{
			print $RepDat1 ("July $ye,$mcomp,$mout");
		}
		if ($mo == 8)
		{
			print $RepDat1 ("August $ye,$mcomp,$mout");
		}
		if ($mo == 9)
		{
			print $RepDat1 ("September $ye,$mcomp,$mout");
		}
		if ($mo == 10)
		{
			print $RepDat1 ("October $ye,$mcomp,$mout");
		}
		if ($mo == 11)
		{
			print $RepDat1 ("November $ye,$mcomp,$mout");
		}
		if ($mo == 12)
		{
			print $RepDat1 ("December $ye,$mcomp,$mout");
		}
		print $RepDat1 "\n";
	}
	for(my $z=0; $z<=7; $z++)
	{
		my $algalgi = $algrow[$z];
		foreach my $altemp (keys(%alg))
		{
			if (!exists($algrow[$z])) #if less than 8 top anoms
			{
				print $RepDat1 "NULL,";
				print $RepDat1 "0,0\n";
				last;
			}
			if ($altemp =~ m/$algalgi/)
			{
				print $RepDat1 "$altemp,".$alg{$altemp}{"CompletedValue"}.",".$alg{$altemp}{"OutstandingValue"}."\n";
				print "$altemp,";
				print ($alg{$altemp}{"CompletedValue"}, ",", $alg{$altemp}{"OutstandingValue"} , "\n");
			}
		}
	}
	for(my $x=0; $x<=7; $x++) #print top AHUs
	{
		$assetahu = $ahurow[$x];
		foreach my $ahtemp (keys(%hashahu)) #each key in %hashahu
		{
			if (!exists($ahurow[$x]))
			{
				print $RepDat1 "NULL,";
				print $RepDat1 "0,0\n";
				last;
			}
			if ($ahtemp =~ m/$assetahu/)
			{
				print $RepDat1 "$ahtemp,";
				print $RepDat1 ($hashahu{$ahtemp}{"Completed"}, ",", $hashahu{$ahtemp}{"Outstanding"} , "\n");
			}
		}
	}
	close($RepDat1);
	#########################################################################################
	########################Three separate files for TreeMapData.csv to be made##############
	#########################################################################################
	
	
	#ANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONEANALYTICS DONE
		#^^^dudeyouneedtorememberyourspaces 
	
	#per-file closing tasks
	my $outputlength = 0;
	if(exists $global{"TT"})
	{
		if(scalar( @{$global{"TT"}}) > scalar( @{$AHU{"TT"}}))
		{
			$outputlength = scalar( @{$global{"TT"}});
		}
		else
		{
			$outputlength = scalar( @{$AHU{"TT"}});
		}
	}
	else
	{
		$outputlength = scalar( @{$AHU{"TT"}});
	}
	for( my $j = 0; ($j < $outputlength) ; $j++)
	{
		foreach my $poo (@colkey)
		{
			if($j < scalar( @{$AHU{"TT"}}))
			{
				if($poo eq "TT") { my $timestring = $AHU{"TT"}[$j]->format_cldr( "MM'/'dd'/'yyyy HH':'mm" ); print CONV "$timestring,";}
				elsif($poo ne "NULL") { print CONV "$AHU{$poo}[$j],"; }
			}
			else
			{
				print CONV "NULL,";
			}
		}
		foreach my $poo (@globalcolkey)
		{
			if($j < scalar( @{$global{"TT"}}))
			{
				if($poo eq "TT") { my $timestring = $global{"TT"}[$j]->format_cldr( "MM'/'dd'/'yyyy HH':'mm" ); print CONV "$timestring,";}
				elsif($poo ne "NULL") { print CONV "$global{$poo}[$j],"; }
			}
			else
			{
				print CONV "NULL,";
			}
		}
		print CONV "\n";
	}
	close (CONV);
	close ($inz);
	for (keys %AHU)	#deletes entire hash after each run so you don't run into crap
    {
        delete $AHU{$_};
    }
	for (keys %{$AHUmap})	#deletes entire hash after each run so you don't run into crap
    {
        delete ${$AHUmap}{$_};
    }
	$excel = 0;	#reset excel flag per file
}
closedir DIR;
close DIAG;
print "\n\n\t\t+-------------------------------------------------+\n";
print "\t\t|diag.txt pointnames.csv totalsavings_save.csv and|\n"; 
print "\t\t|    per AHU savings files have been generated.   |\n";
print "\t\t|  Check diag.txt for all console outputs as well |\n";
print "\t\t|  as additional data and warnings. DIAG MUST BE  |\n";
print "\t\t|CHECKED WITH EVERY RUN SO AS TO CATCH ANY ISSUES.|\n";
print "\t\t+-------------------------------------------------+\n\n\t\t\t       Press enter to close"; 
<STDIN>; #This is to actually capture the enter to close

#Closing Tasks

#pointnames.csv updating code
open (NAME, ">", "pointnames.csv") or die $!;
foreach my $SITE (keys (%stdname))
{
	foreach my $UnitName (keys %{$stdname{$SITE}}) #for every AHU.
	#This loop prints out new/appended/reorganized pointnames.csv
	{
		foreach my $PointName (keys %{$stdname{$SITE}{$UnitName}}) #for every point per AHU
		{
			print NAME "$SITE,$UnitName,$PointName,$stdname{$SITE}{$UnitName}{$PointName},\n";
		}
	}
}
close(NAME);

# open (TOT, ">" ,"totalsavings_save.csv") or die $!;
# #totalsavings_save.csv creation
# print TOT "Site,Unit,";
# foreach my $key (@savingskey)
# {
	# print TOT "$key,";
# }
# print TOT "\n";
# foreach my $AHUname (keys %{$savingstot{$sitename}}) #for every AHU in the site
# #This loop prints out savings
# {
	# print TOT "$sitename,$AHUname,";
	# foreach my $key (@savingskey)
	# {
		# print TOT "$savingstot{$sitename}{$AHUname}{$key},";
	# }
	# print TOT "\n";
# }

print $ft Dumper \%{$ticket}; #print the hash using the reference hash

#print Dumper \%latestAnnul;
print Dumper \%monthlyTicketCounts;
print Dumper \%alg;
print Dumper \%equip;
print Dumper \%ahuhash;

close (TOT);
close($dbg);
close($ft);

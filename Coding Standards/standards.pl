use warnings "all";
use strict;
use Data::Dumper;
use diagnostics -verbose;
#the above MUST be included on commited code. Diagnostics and warnings "all" can be omitted for forks, and for testing, but commited code MUST have the above.

use Scalar::Util qw(looks_like_number);
use DateTime;
#the above are suggested for our application.

print "======================================\n";
#Hash references MUST be initialized as below choice A or B:
my $hashRefA = {};    #choice A, blank, to be populated later
my $hashRefB = {
    "key with scalar" => 1,
    "key with array" => [1, 2, 3],
    "key with another hash" => {
        "another scalar" => 1
    }
};

my %hash = (   
				'elec' => 0,
				'gas' => 0,
				'steam' => 0,
				'active' => 0
			);
my $hashRefC = \%hash;

print Dumper $hashRefB;
print Dumper $hashRefC;
print "======================================\n";
#Hashes must be derefenced as below:

print $hashRefB->{"key with scalar"} == 1; #true
print $hashRefB->{"key with another hash"} ->{"another scalar"} == 1; #true
print $hashRefB->{"key with array"}->[2] == 3; #true
print $hashRefB->{"key with array"}[2] == 3; #arrow may be omitted for ARRAY REFERENCING ONLY
print "\n";
print "======================================\n";
#Hashes must be assigned values as below:
$hashRefA->{"foo"} = "bar";
$hashRefA->{"baz"} = [3, {"shut" => "up\n"}, 1];

print $hashRefA->{"baz"}->[1]->{"shut"}; #up

print Dumper $hashRefA;
print "======================================\n";
#Treating a hash reference as a hash:
#Sometimes you need to grab keys out of a hash reference. Here is how it should be done:

foreach my $poo ( keys(%{ $hashRefB }  ) )
{
    print $poo."\n";
}
print "--------------------------------------\n";
foreach my $poo ( keys(%{ $hashRefA->{"baz"}->[1] }  ) )
{
    print $poo."\n";
}
print "======================================\n";
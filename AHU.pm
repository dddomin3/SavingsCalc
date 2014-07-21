package AHU;
use strict;
use warnings;

#by the way, for some stupid reason, I decided it was a good idea to make dampers count as valves. so they're valves.
sub new
{
    my $class = shift; 
    return bless {_paths => [], _valves => {}, _fans =>{}, _VFDs =>{}}, $class;
}


sub addValve
{
	my $class = shift;
	my $name = shift;
	my $tb = shift;
	my $ta = shift;
	my $min = shift;
	my $max = shift;
	my $energy = shift;
	
	$class->{_valves}{$name} = {
		_tb	=> $tb,
		_ta	=> $ta,
		_min => $min,
		_max => $max,
		_energy => $energy
		};
	
	return 1;
}
			
sub addDamper
{
	my $class = shift;
	my $name = shift;
	my $tb = shift;
	my $ta = shift;
	my $minPer = shift;
	my $maxPer = shift;
	my $minSig = shift;
	my $maxSig = shift;
	my $energy = shift;	#you can probably take this out, although i did set the energy type to 'Damper'. I don't know if that's used anywhere important,
	
	$class->{_valves}{$name} = {
		_tb	=> $tb,
		_ta	=> $ta,
		_minPer => $minPer,
		_maxPer => $maxPer,
		_minSig => $minSig,
		_maxSig => $maxSig,
		_energy => $energy
		};
	
	return 1;
}

sub addFan
{
    my $class = shift;
	my $name = shift;

	$class->{_fans}{$name} = {};
	
    return 1;
}
######################################################################################################################################################################
sub addVFD
{
    my $class = shift;
	my $name = shift;
	my $minVFD = shift;
	my $maxVFD = shift;

		$class->{_VFDs}{$name} = {	#if you're going the _VFD approach, use _VFDs
			_min => $minVFD,
			_max => $maxVFD,
		};
		
    return 1;
}

sub nextValve
{	#TODO: Lots of care needs to be taken if the valve doesn't exist... =\
	my $class = shift;
	my $valve = shift;
	my $nexts = [];
	unless (exists ($class->{_valves}->{$valve}))
	{
		return;
	}
	foreach my $foo (keys %{$class->{_valves}})
	{
		if ($class->{_valves}->{$valve}->{_ta} eq $class->{_valves}->{$foo}->{_tb})
		{
			push @{$nexts}, $foo;
		}
	}
	return $nexts;
}

sub prevValve
{
	my $class = shift;
	my $valve = shift;
	my $prevs = [];
	unless (exists ($class->{_valves}->{$valve}))
	{
		return;
	}
	foreach my $foo (keys %{$class->{_valves}})
	{
		if ($class->{_valves}->{$valve}->{_tb} eq $class->{_valves}->{$foo}->{_ta})
		{
			push @{$prevs}, $foo;
		}
	}
	return $prevs;
}

sub walkValvein #recursive portion of valve walker
{
	my $class = shift;
	my $valve = shift;
	my $rpath = shift; 
	my @path = @$rpath;	#copies reference so it doesn't just have the same thing over and over
	push @path, $valve;

	my $next = $class->nextValve($valve);
	if ( (scalar @$next) == 0 )	#end case. If there is no
	{ 
		push @{$class->{_paths}}, \@path; 
		return; 
	}
	elsif ( (scalar @$next) > 0 )
	{ 	 
		foreach my $foo (@$next)
		{
			$class->walkValvein($foo, \@path);
		}
		return; 
	}
	else
	{
		$class->walkValvein($next, \@path);
		return;
	}
}

sub walkValve #populates _path variable with arrays of valve paths
{
	my $class = shift;
	my $valve = shift;

	my $next = $class->nextValve($valve);
	if ( (scalar @$next) == 0 )
	{
		push @{$class->{_paths}}, [$valve]; 
		return;
	}
	elsif ( (scalar @$next) > 0 )
	{ 	 
		foreach my $foo (@$next)
		{
			$class->walkValvein($foo, [$valve]);
		}
		return; 
	}
}

sub findFirsts
{
	my $class = shift;
	my $firsts = [];
	foreach my $valve (keys %{$class->{_valves}} )
	{
		my $prev = $class->prevValve($valve);
		if ( (scalar @$prev) == 0 )
		{
			push @{$firsts}, $valve;
		}
	}
	return $firsts;
}

sub findLasts
{
	my $class = shift;
	my $lasts = [];
	foreach my $valve (keys %{$class->{_valves}})
	{
		my $next = $class->nextValve($valve);
		if ( (scalar @$next) == 0 )
		{
			push @{$lasts}, $valve;
		}
	}
	return $lasts;
}

sub popPaths
{
	my $class = shift;
	
	my @firsts = @{ $class->findFirsts() };
	foreach my $vlv (@firsts)	{ $class->walkValve($vlv); }
}

sub getvta	#takes in valve string. Outputs the Temp before it
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_ta};
}

sub getvtb	#takes in valve string. Outputs the Temp after it
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_tb};
}

sub getvmin	#takes in valve string. Outputs the min
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_min};
}

sub getvminPer	#takes in valve string. Outputs the max
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_maxPer};
}

sub getvminSig	#takes in valve string. Outputs the max
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_maxSig};
}
sub getvmax	#takes in valve string. Outputs the max
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_max};
}

sub getvmaxPer	#takes in valve string. Outputs the max
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_maxPer};
}

sub getvmaxSig	#takes in valve string. Outputs the max
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_maxSig};
}

sub getvenergy	#takes in valve string. Outputs the energy
{
	my $class = shift;
	my $valve = shift;
	
	return $class->{_valves}->{$valve}->{_energy};
}

sub getvfdmin	#takes in VFD string. Outputs the min
{
	my $class = shift;
	my $VFD = shift;
	
	return $class->{_VFDs}->{$VFD}->{_min};
}

sub getvfdmax	#takes in VFD string. Outputs the max
{
	my $class = shift;
	my $VFD = shift;
	
	return $class->{_VFDs}->{$VFD}->{_max};
}

sub getVlv	#outputs all valves with the character V in it
{
	my $class = shift;
	my @Vlvs;
	foreach my $vlv (keys %{$class->{_valves}})
	{
		if($vlv =~ m/V/)
		{	
			push @Vlvs, $vlv;
		}	
	}
	return @Vlvs;
}

sub getOAD	#outputs all valves with the string PHV in it as an array
{
	my $class = shift;
	my @OADs;
	foreach my $vlv (keys %{$class->{_valves}})
	{

		if($vlv =~ m/OAD/)
		{	
			push @OADs, $vlv;
		}
	}
	return @OADs;
}

sub getPHV	#outputs all valves with the string PHV in it as an array
{
	my $class = shift;
	my @PHVs;
	foreach my $vlv (keys %{$class->{_valves}})
	{

		if($vlv =~ m/PHV/)
		{	
			push @PHVs, $vlv;
		}
	}
	return @PHVs;
}

sub getCCV	#outputs all valves with the string CCV in it as an array
{
	my $class = shift;
	my @CCVs;
	foreach my $vlv (keys %{$class->{_valves}})
	{

		if($vlv =~ m/CCV/)
		{	
			push @CCVs, $vlv;
		}
	}
	return @CCVs;
}

sub getRHV	#outputs all valves with the word RHV in it as an array
{
	my $class = shift;
	my @RHVs;
	foreach my $vlv (keys %{$class->{_valves}})
	{

		if($vlv =~ m/RHV/)
		{	
			push @RHVs, $vlv;
		}
	}
	return @RHVs;
}

sub getSF	#outputs all fans with the word SFS in it as an array
{
	my $class = shift;
	my @SFSs;
	foreach my $fan (keys %{$class->{_fans}})
	{
	
		if($fan =~ m/SFS/)
		{	
			push @SFSs, $fan;
		}
	}
	return @SFSs;
}

sub getSupVFD	#outputs all VFDs with the word SupVFD in it as an array
{
	my $class = shift;
	my @SupVFDs;
	
	foreach my $SupVFD (keys %{$class->{_VFDs}})
	{
		push @SupVFDs, $SupVFD;
	}
	return @SupVFDs;
}

sub getpaths
{
	my $class = shift;
	my @paths;
	
	return @{$class->{_paths}};
}

sub setvta	#takes in valve string, and ta string.
{
	my $class = shift;
	my $valve = shift;
	my $ta = shift;
	
	$class->{_valves}->{$valve}->{_ta} = $ta;
}

sub setvtb	#takes in valve string, and tb string.
{
	my $class = shift;
	my $valve = shift;
	my $tb = shift;
	
	$class->{_valves}->{$valve}->{_tb} = $tb;
}

1;
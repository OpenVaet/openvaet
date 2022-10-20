#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use File::stat;
use JSON;
use Math::Round qw(nearest);
use Scalar::Util qw(looks_like_number);
use Encode;
use Encode::Unicode;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;

# Data Source: https://www.cso.ie/en/statistics/birthsdeathsandmarriages/vitalstatistics/ -> PxStat Tables -> Births and Deaths Registered
# Full Download -> CSV 1.0

# Loading raw data.
my %rawStats  = ();
my $statsFile = 'raw_data/data.cso.ie/VSQ01.20221019T151055.csv';
open my $in, '<:utf8', $statsFile;
while (<$in>) {
	chomp $_;
	$_ =~ s/\"//g;
	my ($code, $statisticType, $tList, $quarterData, $sexCode, $sex, $unit, $value) = split ',', $_;
	# die;
	my ($year, $quarter) = $quarterData =~ /(....)(..)/;
	$quarter =~ s/Q//;
	if ($statisticType eq 'Deaths Registered') {
		# say "$code, $statisticType, $tList, $year, $quarter, $quarterData, $sexCode, $sex, $unit, $value";
	} elsif ($statisticType eq 'Population') {
		# say "$code, $statisticType, $tList, $year, $quarter, $quarterData, $sexCode, $sex, $unit, $value";
	} elsif ($statisticType eq 'Births Registered') {
		# say "$code, $statisticType, $tList, $year, $quarter, $quarterData, $sexCode, $sex, $unit, $value";
	} else {
		next;
	}
	next unless $sex && $sex eq 'Both sexes';
	next unless $value;
	$rawStats{$year}->{$quarter}->{$statisticType}->{'total'} += $value;
}
close $in;
p%rawStats;
my %deathsPer100000 = ();
for my $year (sort{$a <=> $b} keys %rawStats) {
	next unless $year > 2013;
	for my $quarter (sort{$a <=> $b} keys %{$rawStats{$year}}) {
		say "$year - $quarter";
		p$rawStats{$year};
		my $population       = $rawStats{$year}->{$quarter}->{'Population'}->{'total'}        // die;
		my $deathsRegistered = $rawStats{$year}->{$quarter}->{'Deaths Registered'}->{'total'} // die;
		my $per100000        = nearest(0.001, $deathsRegistered * 100000 / $population);
		$deathsPer100000{$quarter}->{$year}->{'per100000'} = $per100000;
		say "$year - $quarter - $population - $deathsRegistered - $per100000";
	}
}

open my $out, '>:utf8', 'stats_by_quarters.csv';
for my $quarter (sort{$a <=> $b} keys %deathsPer100000) {
	my %s = ();
	for my $year (sort{$a <=> $b} keys %{$deathsPer100000{$quarter}}) {
		next unless $year >= 2014 && $year <= 2019;
		my $per100000 = $deathsPer100000{$quarter}->{$year}->{'per100000'} // die;
		# say "$year - $quarter - $per100000";
		$s{'per100000'} += $per100000;
		$s{'years'}++;
	}
	my $per100000Average2014To2019 = nearest(0.001, $s{'per100000'} / $s{'years'});
	my $per100000_2020 = $deathsPer100000{$quarter}->{'2020'}->{'per100000'} // die;
	my $per100000_2021 = $deathsPer100000{$quarter}->{'2021'}->{'per100000'} // die;
	my $per100000_2022 = $deathsPer100000{$quarter}->{'2022'}->{'per100000'} // 'NA';
	# p%s;
	say $out "$quarter;$per100000Average2014To2019;$per100000_2020;$per100000_2021;$per100000_2022;";
	say "per100000Average2014To2019 : $per100000Average2014To2019";
	say "per100000_2020             : $per100000_2020";
	say "per100000_2021             : $per100000_2021";
	say "per100000_2022             : $per100000_2022";
	# die;
}
close $out;
# p%deathsPer100000;
#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Scalar::Util qw(looks_like_number);
use POSIX;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use Encode qw(encode decode);
use JSON;

my %data = load_data();

# Printing population evolution.
my %stats = ();
open my $out1, '>:utf8', 'tasks/sweden/population_by_year.csv';
say $out1 "Year;Population Men;Population Women;Population Total;Births Men;Births Women;Births Total;" .
		  "Last Year Men;Last Year Women;Last Year Total;Offset To Last Year Men;Offset To Last Year Women;Offset To Last Year Total;" .
		  "Deaths Men;Deaths Women;Deaths Total;Birthes Minus Death Men;Birthes Minus Death Women;Birthes Minus Death Total;" .
		  "Evaluated Immigration Offset Men;Evaluated Immigration Offset Women;Evaluated Immigration Offset Total;";
my %lastYearStats = ();
$stats{'births_baselines'}->{'2000-2009'}->{'min_births'}->{'total'} = 999999999999;
$stats{'births_baselines'}->{'2010-2019'}->{'min_births'}->{'total'} = 999999999999;
$stats{'births_baselines'}->{'2000-2009'}->{'max_births'}->{'total'} = 0;
$stats{'births_baselines'}->{'2010-2019'}->{'max_births'}->{'total'} = 0;
$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'min_deaths'}->{'total'} = 999999999999;
$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'min_deaths'}->{'total'} = 999999999999;
$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'max_deaths'}->{'total'} = 0;
$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'max_deaths'}->{'total'} = 0;
for my $year (sort{$a <=> $b} keys %data) {
	my %yearStats = ();
	for my $ageGroup (sort keys %{$data{$year}->{'population'}}) {
		my $men   = $data{$year}->{'population'}->{$ageGroup}->{'men'}   // 0;
		my $women = $data{$year}->{'population'}->{$ageGroup}->{'women'} // 0;
		# p$data{$year}->{'population'}->{$ageGroup};
		$yearStats{'population'}->{'men'}   += $men;
		$yearStats{'population'}->{'women'} += $women;
		$yearStats{'population'}->{'total'} += $men;
		$yearStats{'population'}->{'total'} += $women;
		# die;
	}
	for my $ageGroup (sort keys %{$data{$year}->{'births'}}) {
		my $men   = $data{$year}->{'births'}->{$ageGroup}->{'men'}   // 0;
		my $women = $data{$year}->{'births'}->{$ageGroup}->{'women'} // 0;
		# p$data{$year}->{'births'}->{$ageGroup};
		$yearStats{'births'}->{'men'}   += $men;
		$yearStats{'births'}->{'women'} += $women;
		$yearStats{'births'}->{'total'} += $men;
		$yearStats{'births'}->{'total'} += $women;
		# die;
	}
	for my $ageGroup (sort keys %{$data{$year}->{'deaths'}}) {
		my $men   = $data{$year}->{'deaths'}->{$ageGroup}->{'men'}   // 0;
		my $women = $data{$year}->{'deaths'}->{$ageGroup}->{'women'} // 0;
		my $total = $men + $women;
		# p$data{$year}->{'deaths'}->{$ageGroup};
		$yearStats{'deaths'}->{'men'}   += $men;
		$yearStats{'deaths'}->{'women'} += $women;
		$yearStats{'deaths'}->{'total'} += $men;
		$yearStats{'deaths'}->{'total'} += $women;
		if (looks_like_number $ageGroup && ($ageGroup < 1)) {
			if ($year >= 2000 && $year <= 2009) {
				$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'deaths'}->{'totalYears'}++;
				$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'deaths'}->{'total'} += $total;
				if ($stats{'infant_deaths_baseline'}->{'2000-2009'}->{'min_deaths'}->{'total'} > $total) {
					$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'min_deaths'}->{'total'} = $total;
				}
				if ($stats{'infant_deaths_baseline'}->{'2000-2009'}->{'max_deaths'}->{'total'} < $total) {
					$stats{'infant_deaths_baseline'}->{'2000-2009'}->{'max_deaths'}->{'total'} = $total;
				}
			} elsif ($year >= 2010 && $year <= 2019) {
				$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'deaths'}->{'totalYears'}++;
				$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'deaths'}->{'total'} += $total;
				if ($stats{'infant_deaths_baseline'}->{'2010-2019'}->{'min_deaths'}->{'total'} > $total) {
					$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'min_deaths'}->{'total'} = $total;
				}
				if ($stats{'infant_deaths_baseline'}->{'2010-2019'}->{'max_deaths'}->{'total'} < $total) {
					$stats{'infant_deaths_baseline'}->{'2010-2019'}->{'max_deaths'}->{'total'} = $total;
				}
			} else {
				$stats{'yearly_infant_deaths'}->{$year}->{'deaths'}->{'totalYears'}++;
				$stats{'yearly_infant_deaths'}->{$year}->{'deaths'}->{'total'} = $total;
			}
		}
		# die;
	}
	my $birthsMen       = $yearStats{'births'}->{'men'}       // 0;
	my $birthsWomen     = $yearStats{'births'}->{'women'}     // 0;
	my $birthsTotal     = $yearStats{'births'}->{'total'}     // 0;
	if ($year >= 2000 && $year <= 2009) {
		$stats{'births_baselines'}->{'2000-2009'}->{'births'}->{'totalYears'}++;
		$stats{'births_baselines'}->{'2000-2009'}->{'births'}->{'total'} += $birthsTotal;
		if ($stats{'births_baselines'}->{'2000-2009'}->{'min_births'}->{'total'} > $birthsTotal) {
			$stats{'births_baselines'}->{'2000-2009'}->{'min_births'}->{'total'} = $birthsTotal;
		}
		if ($stats{'births_baselines'}->{'2000-2009'}->{'max_births'}->{'total'} < $birthsTotal) {
			$stats{'births_baselines'}->{'2000-2009'}->{'max_births'}->{'total'} = $birthsTotal;
		}
	} elsif ($year >= 2010 && $year <= 2019) {
		$stats{'births_baselines'}->{'2010-2019'}->{'births'}->{'totalYears'}++;
		$stats{'births_baselines'}->{'2010-2019'}->{'births'}->{'total'} += $birthsTotal;
		if ($stats{'births_baselines'}->{'2010-2019'}->{'min_births'}->{'total'} > $birthsTotal) {
			$stats{'births_baselines'}->{'2010-2019'}->{'min_births'}->{'total'} = $birthsTotal;
		}
		if ($stats{'births_baselines'}->{'2010-2019'}->{'max_births'}->{'total'} < $birthsTotal) {
			$stats{'births_baselines'}->{'2010-2019'}->{'max_births'}->{'total'} = $birthsTotal;
		}
	} else {
		$stats{'yearly_births'}->{$year}->{'births'}->{'totalYears'}++;
		$stats{'yearly_births'}->{$year}->{'births'}->{'total'} = $birthsTotal;
	}
	my $deathsMen       = $yearStats{'deaths'}->{'men'}       // 0;
	my $deathsWomen     = $yearStats{'deaths'}->{'women'}     // 0;
	my $deathsTotal     = $yearStats{'deaths'}->{'total'}     // 0;
	my $populationMen   = $yearStats{'population'}->{'men'}   // 0;
	my $populationWomen = $yearStats{'population'}->{'women'} // 0;
	my $populationTotal = $yearStats{'population'}->{'total'} // 0;
	my $birthMinusDeathMen   = $birthsMen   - $deathsMen;
	my $birthMinusDeathWomen = $birthsWomen - $deathsWomen;
	my $birthMinusDeathTotal = $birthsTotal - $deathsTotal;
	$stats{'global_stats'}->{$year}->{'population'}->{'total'}->{'men'} = $populationMen;
	$stats{'global_stats'}->{$year}->{'population'}->{'total'}->{'women'} = $populationWomen;
	$stats{'global_stats'}->{$year}->{'population'}->{'total'}->{'total'} = $populationTotal;
	$stats{'global_stats'}->{$year}->{'births'}->{'total'}->{'men'} = $birthsMen;
	$stats{'global_stats'}->{$year}->{'births'}->{'total'}->{'women'} = $birthsWomen;
	$stats{'global_stats'}->{$year}->{'births'}->{'total'}->{'total'} = $birthsTotal;
	my ($lastYearMen, $lastYearWomen, $lastYearTotal) = ('', '', '');
	my ($offsetToLastYearMen, $offsetToLastYearWomen, $offsetToLastYearTotal) = ('', '', '');
	my ($evaluatedImmigrationOffsetMen, $evaluatedImmigrationOffsetWomen, $evaluatedImmigrationOffsetTotal) = ('', '', '');
	if (keys %lastYearStats) {
		$lastYearMen   = $lastYearStats{'population'}->{'total'}->{'men'}   // die;
		$lastYearWomen = $lastYearStats{'population'}->{'total'}->{'women'} // die;
		$lastYearTotal = $lastYearStats{'population'}->{'total'}->{'total'} // die;
		$offsetToLastYearTotal = $populationTotal - $lastYearTotal;
		$offsetToLastYearWomen = $populationWomen - $lastYearWomen;
		$offsetToLastYearMen   = $populationMen   - $lastYearMen;
		$evaluatedImmigrationOffsetTotal = $offsetToLastYearTotal - $birthMinusDeathTotal;
		$evaluatedImmigrationOffsetWomen = $offsetToLastYearWomen - $birthMinusDeathWomen;
		$evaluatedImmigrationOffsetMen   = $offsetToLastYearMen   - $birthMinusDeathMen;
	}
	$lastYearStats{'population'}->{'total'}->{'men'}   = $populationMen;
	$lastYearStats{'population'}->{'total'}->{'women'} = $populationWomen;
	$lastYearStats{'population'}->{'total'}->{'total'} = $populationTotal;
	say $out1 "$year;$populationMen;$populationWomen;$populationTotal;$birthsMen;$birthsWomen;$birthsTotal;" .
			  "$lastYearMen;$lastYearWomen;$lastYearTotal;$offsetToLastYearMen;$offsetToLastYearWomen;$offsetToLastYearTotal;" .
			  "$deathsMen;$deathsWomen;$deathsTotal;$birthMinusDeathMen;$birthMinusDeathWomen;$birthMinusDeathTotal;" .
			  "$evaluatedImmigrationOffsetMen;$evaluatedImmigrationOffsetWomen;$evaluatedImmigrationOffsetTotal;";
	# say "year : $year";
	# p%yearStats;
	# die;
}
close $out1;
say "births baselines :";
p$stats{'births_baselines'};
say "births yearly :";
p$stats{'yearly_births'};
say "deaths baselines :";
p$stats{'infant_deaths_baseline'};
say "deaths yearly :";
p$stats{'yearly_infant_deaths'};

sub load_data {
	my $json;
	open my $in, '<:utf8', 'tasks/sweden/swedish_data.json';
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	return %$json;
}
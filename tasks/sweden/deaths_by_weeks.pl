#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use POSIX;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use Encode qw(encode decode);
use JSON;
use Math::Round qw(nearest);
use List::Util qw(sum);
use Scalar::Util qw(looks_like_number);

# Weekly deaths are taken on https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101I/DodaVeckaRegion/
my $deaths_by_weeks       = 'tasks/sweden/deaths_by_weeks.csv';
# Population are taken on https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101A/BefolkningR1860N/
my $population            = 'tasks/sweden/population.csv';
# COVID-19 deaths are taken on 
my $covid_deaths_by_weeks = 'tasks/sweden/covid_deaths.csv';

# Initiating a few arrays required to parse the .CSV.
my @years;
push @years, $_ for (2010 .. 2023);
my @weeks = ('01', '02', '03', '04', '05', '06', '07', '08', '09');
push @weeks, $_ for (10 .. 53);

# Will store the structured raw data.
my %deaths_by_weeks       = ();
my %population            = ();
my %covid_deaths_by_weeks = ();

# Loading raw data.
load_population();
load_weekly_deaths();
load_covid_deaths_by_weeks();

open my $out1, '>:utf8', 'tasks/sweden/deaths_by_weeks_stats.csv';
open my $out2, '>:utf8', 'tasks/sweden/deaths_by_weeks_stats_total.csv';
say $out1 "age_group;year;week_group;baseline_average;std;deaths_per_100k;z_score;";
say $out2 "age_group;year;week_group;baseline_average;std;deaths_per_100k;z_score;covid_deaths;deaths;percent_covid_deaths;";
for my $age_group (sort keys %deaths_by_weeks){
	my %stats = ();
	for my $year (sort{$a <=> $b} keys %{$deaths_by_weeks{$age_group}}) {
		for my $week_group (sort{$a <=> $b} keys %{$deaths_by_weeks{$age_group}->{$year}}) {
			my $deaths               = $deaths_by_weeks{$age_group}->{$year}->{$week_group}->{'total'} // die;
			my $age_group_population = $population{$year}->{$age_group}                                // next;
			my $deaths_per_100000    = $deaths * 100000 / $age_group_population;
			if ($year <= 2019) {
				push @{$stats{'baseline'}->{$week_group}->{'deaths_per_100000'}}, $deaths_per_100000;
			} else {
				# To compare with baseline.
				my $baseline_deaths = $stats{'baseline'}->{$week_group}->{'deaths_per_100000'} // die;
				my $mean = sum(@$baseline_deaths) / @$baseline_deaths;
				my $sqsum = sum(map {($_-$mean)**2} @$baseline_deaths);
				my $std = sqrt($sqsum / (@$baseline_deaths-1));
				my $z = ($deaths_per_100000 - $mean) / $std;
				if ($age_group eq 'total') {
					my $covid_deaths = $covid_deaths_by_weeks{$year}->{$week_group}->{'total'} // 0;
					my $percent_covid_deaths = nearest(0.01, $covid_deaths * 100 / $deaths);
					say $out2 "$age_group;$year;$week_group;$mean;$std;$deaths_per_100000;$z;$covid_deaths;$deaths;$percent_covid_deaths;";
				} else {
					say $out1 "$age_group;$year;$week_group;$mean;$std;$deaths_per_100000;$z;";
				}
			}
		}
	}
}
close $out1;
close $out2;

sub load_population {
	open my $in, '<:utf8', $population;
	my %labels = ();
	my $lNum   = 0;
	while (<$in>) {
		chomp $_;
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}
		$lNum++;
		if ($lNum == 1) {
			my @elems = split ';', $line;
			my $eNum  = 0;
			for my $elem (@elems) {
				$eNum++;
				$elem =~ s/\"//g;
				$labels{$eNum} = $elem;
			}
		} else {
			my %values = ();
			my @elems  = split ';', $line;
			my $eNum   = 0;
			for my $elem (@elems) {
				$eNum++;
				my $label = $labels{$eNum} // die;
				$elem =~ s/\"//g;
				$values{$label} = $elem;
			}
			my $age = $values{'age'} // die;
			$age    =~ s/ year//;
			$age    =~ s/ years//;
			$age    =~ s/s//;
			$age    =~ s/\+//;
			my $age_group = group_from_age($age);
			my $sex = $values{'sex'} // die;
			for my $year (@years) {
				my $population = $values{$year} // next;
				$population{$year}->{$age_group} += $population;
				$population{$year}->{'total'} += $population;
			}
		}
	}
	close $in;
}

sub group_from_age {
	my $age = shift;
	unless (looks_like_number $age) {
		die "age : $age";
	}
	my $age_group;
	if ($age >= 0       && $age <= 34) {
		$age_group = '0-34 years';
	} elsif ($age >= 35 && $age <= 59) {
		$age_group = '35-59 years';
	} elsif ($age >= 60 && $age <= 69) {
		$age_group = '60-69 years';
	} elsif ($age >= 70 && $age <= 79) {
		$age_group = '70-79 years';
	} elsif ($age >= 80 && $age <= 89) {
		$age_group = '80-89 years';
	} elsif ($age >= 90) {
		$age_group = '90+ years';
	} else {
		die "age : $age";
	}
	return $age_group;
}

sub load_weekly_deaths {
	open my $in, '<:utf8', $deaths_by_weeks;
	my %labels = ();
	my $lNum   = 0;
	while (<$in>) {
		chomp $_;
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}
		$lNum++;
		if ($lNum == 1) {
			my @elems = split ';', $line;
			my $eNum  = 0;
			for my $elem (@elems) {
				$eNum++;
				$elem =~ s/\"//g;
				$labels{$eNum} = $elem;
			}
		} else {
			my %values = ();
			my @elems  = split ';', $line;
			my $eNum   = 0;
			for my $elem (@elems) {
				$eNum++;
				my $label = $labels{$eNum} // die;
				$elem =~ s/\"//g;
				$values{$label} = $elem;
			}
			my $age = $values{'age'} // die;
			my $sex = $values{'sex'} // die;
			for my $year (@years) {
				for my $week (@weeks) {
					my $label = $year . "V$week";
					# say "label : $label";
					my $value = $values{$label} // next;
					my $week_group = group_from_week($week);
					$deaths_by_weeks{$age}->{$year}->{$week_group}->{'sexes'}->{$sex} += $value;
					$deaths_by_weeks{$age}->{$year}->{$week_group}->{'total'} += $value;
					# say "$age - $sex - $year - $week - $label - $value";
				}
			}
		}
	}
	close $in;
}

sub load_covid_deaths_by_weeks {
	open my $in, '<:utf8', $covid_deaths_by_weeks;
	my %labels = ();
	my $lNum   = 0;
	while (<$in>) {
		chomp $_;
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}
		$lNum++;
		if ($lNum == 1) {
			my @elems = split ';', $line;
			my $eNum  = 0;
			for my $elem (@elems) {
				$eNum++;
				$elem =~ s/\"//g;
				$labels{$eNum} = $elem;
			}
		} else {
			my %values = ();
			my @elems  = split ';', $line;
			my $eNum   = 0;
			for my $elem (@elems) {
				$eNum++;
				my $label = $labels{$eNum} // die;
				$elem =~ s/\"//g;
				$values{$label} = $elem;
			}
			my $week_year = $values{'week'} // die;
			my ($year, $week) = split 'v', $week_year;
			my $week_group = group_from_week($week);
			die unless $year && $week;
			my $covid_deaths = $values{'covid_deaths'} // die;
			$covid_deaths_by_weeks{$year}->{$week_group}->{'total'} += $covid_deaths;
		}
	}
	close $in;
}

sub group_from_week {
	my $week = shift;
	my $week_group;
	if ($week >= 1 && $week <= 4) {
		$week_group = 1;
	} elsif ($week >= 5 && $week <= 8) {
		$week_group = 2;
	} elsif ($week >= 9 && $week <= 12) {
		$week_group = 3;
	} elsif ($week >= 13 && $week <= 16) {
		$week_group = 4;
	} elsif ($week >= 17 && $week <= 20) {
		$week_group = 5;
	} elsif ($week >= 21 && $week <= 24) {
		$week_group = 6;
	} elsif ($week >= 25 && $week <= 28) {
		$week_group = 7;
	} elsif ($week >= 29 && $week <= 32) {
		$week_group = 8;
	} elsif ($week >= 33 && $week <= 36) {
		$week_group = 9;
	} elsif ($week >= 37 && $week <= 40) {
		$week_group = 10;
	} elsif ($week >= 41 && $week <= 44) {
		$week_group = 11;
	} elsif ($week >= 45 && $week <= 48) {
		$week_group = 12;
	} elsif ($week >= 49 && $week <= 53) {
		$week_group = 13;
	} else {
		die "week : $week";
	}

}
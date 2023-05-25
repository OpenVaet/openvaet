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

# Deaths are taken from https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101I/DodaHandelseK/
# Region Sweden - 00 Sweden
# age - Age, 1 year age classes - 0 to 100+ years
# sex Men + Women
# Year 2000 - 2022
my $deaths = 'tasks/sweden/deaths.csv';
# Births are taken from https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101H/FoddaK/
# Region Sweden - 00 Sweden
# age of the Mother - Ålder, 1-årsklasser och 2 grupper
# sex Men + Women
# Year 2000 - 2022
my $births = 'tasks/sweden/births.csv';
# Deaths by region & place of birth can be obtained on https://www.statistikdatabasen.scb.se/pxweb/sv/ssd/START__BE__BE0101__BE0101I/DodaManadReg/
# table contents : Age at death
# region : the Kingdom
# region of birth : born in Sweden
# other filters : "Select all"
my $deathsByBirthPlace = '';
# Population are taken on https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101A/BefolkningR1860N/
# Age : One year age classes -> Select all
# Sex Men + Women
# Years : 2000 => 2022
my $population = 'tasks/sweden/population.csv';
# Weekly deaths are taken on https://www.statistikdatabasen.scb.se/pxweb/en/ssd/START__BE__BE0101__BE0101I/DodaVeckaRegion/
my $deaths_by_weeks = 'tasks/sweden/deaths_by_weeks.csv';


my %data       = ();
my %years      = ();
for my $year (2000 ... 2022) {
	$years{$year} = 1;
}

load_deaths();
load_births();
load_population();
# p%data;

open my $out, '>:utf8', 'tasks/sweden/swedish_data.json';
print $out encode_json\%data;
close $out;
# p%deaths;

sub load_deaths {
	open my $in, '<:utf8', $deaths;
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
			$age =~ s/ years//;
			my $sex = $values{'sex'} // die;
			for my $year (sort{$a <=> $b} keys %years) {
				my $deaths = $values{$year} // die;
				$data{$year}->{'deaths'}->{$age}->{$sex} = $deaths;
			}
		}
	}
	close $in;
}

sub load_births {
	open my $in, '<:utf8', $births;
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
			my $age = $values{'age of the Mother'} // die;
			$age =~ s/ years//;
			my $sex = $values{'sex'} // die;
			for my $year (sort{$a <=> $b} keys %years) {
				my $births = $values{$year} // die;
				$data{$year}->{'births'}->{$age}->{$sex} = $births;
			}
		}
	}
	close $in;
}

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
			$age =~ s/ years//;
			my $sex = $values{'sex'} // die;
			for my $year (sort{$a <=> $b} keys %years) {
				my $population = $values{$year} // die;
				$data{$year}->{'population'}->{$age}->{$sex} = $population;
			}
		}
	}
	close $in;
}
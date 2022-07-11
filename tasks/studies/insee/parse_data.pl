#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use JSON;
use Math::Round qw(nearest);
use Encode;
use Encode::Unicode;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;

my $deathesFolder = "tasks/studies/insee/deaths_data";

my %statistics    = ();

for my $file (glob "$deathesFolder/*") {
	my $year;
	if ($file =~ /.*_.*_.*/) {
		(undef, $year, undef) = split '_', $file;
	} elsif ($file =~ /.*_.*/) {
		(undef, $year) = split '_', $file;
	} else {
		die;
	}
	($year) = split '\.', $year;
	# next unless $year >= 2017;
	my %dataLabels     = ();
	my $expectedValues = 0;
	say "year  : [$year]";
	say $file;
	my $dRNum   = 0;
	open my $in, '<:utf8', $file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\¤/n/g;
		$_ =~ s/‚cŠs/CSS/g;
		$_ =~ s/\²/2/g;
		$_ =~ s/\°/\)/g;
		$_ =~ s/\¨/A/g;
		$_ =~ s/Â\)/A/g;
		$_ =~ s/å/a/g;
		$_ =~ s/Â/a/g;
		$_ =~ s/à/a/g;
		$_ =~ s/ã/a/g;
		$_ =~ s/Ç/C/g;
		$_ =~ s/¿/C/g;
		$_ =~ s/ïC½/e/g;
		$_ =~ s/Ã©/e/g;
		$_ =~ s/ÃA/e/g;
		$_ =~ s/é/e/g;
		$_ =~ s/è/e/g;
		$_ =~ s/ø/o/g;
		$_ =~ s/µ/u/g;
		$_ =~ s/Ü/U/g;
		$_ =~ s/ý/y/g;
		$_ =~ s/¥/y/g;
		$_ =~ s/MARBURG A\.D; LAHN/MARBURG A\.D LAHN/g;
		$_ =~ s/LLOMBAY; PROVINCE/LLOMBAY, PROVINCE/g;
		$_ =~ s/NDAABED; AIT/NDAABED, AIT/g;
		$_ =~ s/CHIKER; NADOR/CHIKER, NADOR/g;
		$_ =~ s/PALMEIRA ; MATOSINHOS/PALMEIRA, MATOSINHOS/g;
		$_ =~ s/FAFE ; FAFE/FAFE, FAFE/g;
		$_ =~ s/BENESPERA ; GUARDA/BENESPERA, GUARDA/g;
		$_ =~ s/VILARINHO; SANTO/VILARINHO, SANTO/g;
		$_ =~ s/DEUX PONTS ; PALATINAT/DEUX PONTS, PALATINAT/g;
		$_ =~ s/CARGEDOLO; PROVINCE/CARGEDOLO, PROVINCE/g;
		$_ =~ s/BOUAIR ; COMMU/BOUAIR, COMMU/g;
		$_ =~ s/SANDIM; VILA/SANDIM, VILA/g;
		$_ =~ s/BARROSO; BOTICAS/BARROSO, BOTICAS/g;
		$_ =~ s/CASTANHEIRA; CARR/CASTANHEIRA, CARR/g;
		$_ =~ s/IKDMANE ; AIT/IKDMANE, AIT/g;
		$_ =~ s/PORTILLO ; VALLADOLID/PORTILLO, VALLADOLID/g;
		$_ =~ s/FRIO ; ARCOS/FRIO, ARCOS/g;
		$_ =~ s/GOUVINHAS; ARRONDISSEM/GOUVINHAS, ARRONDISSEM/g;
		$_ =~ s/IDAES; FELGUEIRAS/IDAES, FELGUEIRAS/g;
		$_ =~ s/ALTURAS ; BOTICAS/ALTURAS, BOTICAS/g;
		$_ =~ s/RHUMEL ; CONSTAN/RHUMEL, CONSTAN/g;
		$_ =~ s/CARREIRAS; PORTALEGRE/CARREIRAS, PORTALEGRE/g;
		$_ =~ s/LA CHAUX-DE-FONDS ; LE LOCLE/LA CHAUX-DE-FONDS, LE LOCLE/g;
		$_ =~ s/ODIVELAS; LOURES/ODIVELAS, LOURES/g;
		$_ =~ s/CAMPO; CASTELO/CAMPO, CASTELO/g;
		$_ =~ s/BARACAL; CELORICO/BARACAL, CELORICO/g;
		$_ =~ s/UENDER RERHIOUA ; TAOUNA/UENDER RERHIOUA, TAOUNA/g;
		$_ =~ s/­//g;
		$_ =~ s/ //g;
		$_ =~ s///g;
		$_ =~ s///g;
		# say '$_ : ' . $_;
		$dRNum++;

		# Verifying line.
		my $line = $_;
		$line =~ s/\"//g;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
			say $line;
		    printf "In [$file], bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			my @labels = split ';', $line;
			my $lN = 0;
			for my $label (@labels) {
				$dataLabels{$lN} = $label;
				$lN++;
			}
			$expectedValues = keys %dataLabels;
		} else {

			# Verifying we have the expected number of values.
			my @values = split ';', $line;
			my $vN  = 0;
			my %values = ();
			for my $value (@values) {
				my $label = $dataLabels{$vN} // die "line : $line";
				$values{$label} = $value;
				$vN++;
			}
			my $name         = $values{'nomprenom'} // die "line : $line";
			my $sex          = $values{'sexe'}      // die "line : $line";
			my $birthCity    = $values{'commnaiss'} // die "line : $line";
			my $birthDate    = $values{'datenaiss'} // die "line : $line";
			my ($birthYear,
				$birthMonth,
				$birthDay)   = $birthDate =~ /(....)(..)(..)/;
			die unless $birthYear && $birthMonth && $birthDay;
			if ($birthMonth  eq '00') {
				$birthMonth  = '01';
			}
			if ($birthDay    eq '00') {
				$birthDay    = '01';
			}
			$birthDate       = "$birthYear-$birthMonth-$birthDay";
			if ($birthDate  eq '1898-02-29') {
				$birthDay    = '28';
				$birthMonth  = '02';
				$birthYear   = '1898';
			}
			my $birthPlace   = $values{'lieunaiss'} // die "line : $line";
			my $birthCountry = $values{'paysnaiss'} // die "line : $line";
			my $deathDate    = $values{'datedeces'} // die "line : $line";
			my ($deathYear,
				$deathMonth,
				$deathDay)   = $deathDate =~ /(....)(..)(..)/;
			if (!$deathDay && $deathDate =~ /....../) {
				($deathYear,
				$deathMonth) = $deathDate =~ /(....)(..)/;
				$deathDay    = '01';
			}
			die "deathDate : $deathDate" unless $deathYear && $deathMonth && $deathDay;
			if ($deathMonth  eq '00') {
				$deathMonth  = '01';
			}
			if ($deathDay    eq '00') {
				$deathDay    = '01';
			}
			$deathDate       = "$deathYear-$deathMonth-$deathDay";
			if ($birthYear < 1900) {
				$statistics{'invalidBirthYear'}++;
				next;
			}
			if ($deathYear < 2010) {
				$statistics{'outOfScope'}++;
				next;
			}
			my $deathPlace   = $values{'lieudeces'} // die "line : $line";
			my ($lastName, $firstName) = split '\*', $name;
			if ($name eq 'MARIE ANTOINE JOSEPH DIT MARIE ANTOINE JOSEPH ALIAS SOOSAIRAJ DIT AUSSI MARIE J/') {
				$firstName = 'MARIE ANTOINE';
				$lastName  = 'JOSEPH';
			}
			die "name : [$name]" unless $firstName;
			$firstName       =~ s/\/$//;
			# say "firstName    : $firstName";
			# say "lastName     : $lastName";
			# say "sex          : $sex";
			# say "birthCity    : $birthCity";
			# say "birthDate    : $birthDate";
			# say "birthPlace   : $birthPlace";
			# say "birthCountry : $birthCountry";
			# say "deathDate    : $deathDate";
			# say "deathPlace   : $deathPlace";
			my $ageInMinutes = time::calculate_minutes_difference($birthDate . ' 12:00:00', $deathDate . ' 12:00:00');
			my $ageInDays    = nearest(1, $ageInMinutes / 60 / 24);
			my $ageInYears   = nearest(0.01, $ageInDays    / 365);
			my $sexName;
			if ($sex == 1) {
				$sexName = 'Male';
			} else {
				$sexName = 'Female';
			}
			my ($ageGroup5Name, $ageGroup10Name);
			if ($ageInDays <= 365) {
				$ageGroup5Name  = "Under 1 Year Old";
				$ageGroup10Name = "Under 1 Year Old";
			} elsif ($ageInDays > 365 && $ageInYears <= 2) {
				$ageGroup5Name = "1 Year to 2 Years Old";
				$ageGroup10Name = "1 Year to 10 Years Old";
			} elsif ($ageInYears > 2 && $ageInYears <= 5) {
				$ageGroup5Name = "2 Years to 5 Years Old";
				$ageGroup10Name = "1 Year to 10 Years Old";
			} elsif ($ageInYears > 5 && $ageInYears <= 10) {
				$ageGroup5Name = "5 Years to 10 Years Old";
				$ageGroup10Name = "1 Year to 10 Years Old";
			} elsif ($ageInYears > 10 && $ageInYears <= 15) {
				$ageGroup5Name = "10 Years to 15 Years Old";
				$ageGroup10Name = "10 Year to 20 Years Old";
			} elsif ($ageInYears > 15 && $ageInYears <= 20) {
				$ageGroup5Name = "15 Years to 20 Years Old";
				$ageGroup10Name = "10 Year to 20 Years Old";
			} elsif ($ageInYears > 20 && $ageInYears <= 25) {
				$ageGroup5Name = "20 Years to 25 Years Old";
				$ageGroup10Name = "20 Year to 30 Years Old";
			} elsif ($ageInYears > 25 && $ageInYears <= 30) {
				$ageGroup5Name = "25 Years to 30 Years Old";
				$ageGroup10Name = "20 Year to 30 Years Old";
			} elsif ($ageInYears > 30 && $ageInYears <= 35) {
				$ageGroup5Name = "30 Years to 35 Years Old";
				$ageGroup10Name = "30 Year to 40 Years Old";
			} elsif ($ageInYears > 35 && $ageInYears <= 40) {
				$ageGroup5Name = "35 Years to 40 Years Old";
				$ageGroup10Name = "30 Year to 40 Years Old";
			} elsif ($ageInYears > 40 && $ageInYears <= 45) {
				$ageGroup5Name = "40 Years to 45 Years Old";
				$ageGroup10Name = "45 Year to 50 Years Old";
			} elsif ($ageInYears > 45 && $ageInYears <= 50) {
				$ageGroup5Name = "45 Years to 50 Years Old";
				$ageGroup10Name = "45 Year to 50 Years Old";
			} elsif ($ageInYears > 50 && $ageInYears <= 55) {
				$ageGroup5Name = "50 Years to 55 Years Old";
				$ageGroup10Name = "50 Year to 60 Years Old";
			} elsif ($ageInYears > 55 && $ageInYears <= 60) {
				$ageGroup5Name = "55 Years to 60 Years Old";
				$ageGroup10Name = "50 Year to 60 Years Old";
			} elsif ($ageInYears > 60 && $ageInYears <= 65) {
				$ageGroup5Name = "60 Years to 65 Years Old";
				$ageGroup10Name = "60 Year to 70 Years Old";
			} elsif ($ageInYears > 65 && $ageInYears <= 70) {
				$ageGroup5Name = "65 Years to 70 Years Old";
				$ageGroup10Name = "60 Year to 70 Years Old";
			} elsif ($ageInYears > 70 && $ageInYears <= 75) {
				$ageGroup5Name = "70 Years to 75 Years Old";
				$ageGroup10Name = "70 Year to 80 Years Old";
			} elsif ($ageInYears > 75 && $ageInYears <= 80) {
				$ageGroup5Name = "75 Years to 80 Years Old";
				$ageGroup10Name = "70 Year to 80 Years Old";
			} elsif ($ageInYears > 80 && $ageInYears <= 85) {
				$ageGroup5Name = "80 Years to 85 Years Old";
				$ageGroup10Name = "80 Year to 90 Years Old";
			} elsif ($ageInYears > 85 && $ageInYears <= 90) {
				$ageGroup5Name = "85 Years to 90 Years Old";
				$ageGroup10Name = "80 Year to 90 Years Old";
			} elsif ($ageInYears > 90 && $ageInYears <= 95) {
				$ageGroup5Name = "90 Years to 95 Years Old";
				$ageGroup10Name = "90 Year to 100 Years Old";
			} elsif ($ageInYears > 95 && $ageInYears <= 100) {
				$ageGroup5Name = "95 Years to 100 Years Old";
				$ageGroup10Name = "90 Year to 100 Years Old";
			} elsif ($ageInYears > 100 && $ageInYears <= 105) {
				$ageGroup5Name = "100 Years to 105 Years Old";
				$ageGroup10Name = "100 Year to 110 Years Old";
			} elsif ($ageInYears > 105 && $ageInYears <= 110) {
				$ageGroup5Name = "105 Years to 110 Years Old";
				$ageGroup10Name = "100 Year to 110 Years Old";
			} elsif ($ageInYears > 110 && $ageInYears <= 115) {
				$ageGroup5Name = "110 Years to 115 Years Old";
				$ageGroup10Name = "110 Year to 120 Years Old";
			} elsif ($ageInYears > 115 && $ageInYears <= 120) {
				$ageGroup5Name = "115 Years to 120 Years Old";
				$ageGroup10Name = "110 Year to 120 Years Old";
			} elsif ($ageInYears > 120 && $ageInYears <= 125) {
				$ageGroup5Name = "120 Years to 125 Years Old";
				$ageGroup10Name = "120 Year to 130 Years Old";
			} else {
				say "birthDate    : $birthDate";
				say "deathDate    : $deathDate";
				say "ageInDays  : $ageInDays";
				die "ageInYears : $ageInYears";
			}
			# say "name         : $name";
			# say "ageInMinutes : $ageInMinutes";
			# say "sexName      : $sexName";
			# say "ageInDays    : $ageInDays";
			# say "ageInYears   : $ageInYears";
			# say "ageGroupName : $ageGroupName";
			# $statistics{$deathYear}->{$sexName}->{$ageGroupName}++;
			$statistics{$deathYear}->{'global'}->{'anySex'}++;
			$statistics{$deathYear}->{'global'}->{$sexName}++;
			$statistics{$deathYear}->{'byAges5'}->{$ageGroup5Name}->{'anySex'}++;
			$statistics{$deathYear}->{'byAges5'}->{$ageGroup5Name}->{$sexName}++;
			$statistics{$deathYear}->{'byAges10'}->{$ageGroup10Name}->{'anySex'}++;
			$statistics{$deathYear}->{'byAges10'}->{$ageGroup10Name}->{$sexName}++;
			# p%values;
			# die;
		}
	}
	close $in;
	say "dRNum : $dRNum";
}
p%statistics;
open my $out, '>:utf8', 'stats/insee_deathes_data.json' or die $!;
print $out encode_json\%statistics;
close $out;
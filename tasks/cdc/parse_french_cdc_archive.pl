#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use Data::Printer;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use global;
use time;
use cdc;

my $sourceId    = 2;                               # DB hard-coded corresponding value.
my $cdcFolder   = "raw_data/NonDomesticVAERSData"; # Where we expect to find CDC's data folder in the project's root folder, from https://vaers.hhs.gov/eSubDownload/index.jsp?fn=NonDomesticVAERSData.zip
my $statesFile  = "tasks/cdc/states.csv";          # File containing CDC's states.

# Verifies we have the expected folder.
unless (-d $cdcFolder) {
	say "No CDC data found on $cdcFolder. Exiting";
	exit;
}

# For each year, reading reports, symptoms related, and vaccines related.
my $rawDataOut   = 'raw_data/VAERSFrenchReports/FrenchReportsVAERSDATA.csv';
my $rawSymptOut  = 'raw_data/VAERSFrenchReports/FrenchReportsVAERSSYMPTOMS.csv';
my $rawVaxOut    = 'raw_data/VAERSFrenchReports/FrenchReportsVAERSVAX.csv';
parse_non_domestic_data();

sub parse_non_domestic_data {

	# Configuring expected files ; dying if they aren't found.
	my $dataFile     = "$cdcFolder/NonDomesticVAERSDATA.csv";
	my $symptomsFile = "$cdcFolder/NonDomesticVAERSSYMPTOMS.csv";
	my $vaccinesFile = "$cdcFolder/NonDomesticVAERSVAX.csv";
	die "missing mandatory file in [$cdcFolder]" if !-f $dataFile || !-f $symptomsFile || !-f $vaccinesFile;
	say "dataFile     : $dataFile";
	say "symptomsFile : $symptomsFile";
	say "vaccinesFile : $vaccinesFile";

	# Fetching notices.
	open my $dataIn, '<:', $dataFile;
	my $dRNum = 0;
	my %dataLabels = ();
	my $expectedValues = ();
	my $dataCsv = Text::CSV_XS->new ({ binary => 1 });
	my $frenchReports = 0;
	my %statistics = ();
	my %frenchReports = ();
	open my $out, '>:utf8', $rawDataOut;
	while (<$dataIn>) {
		$dRNum++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s/\r//g;
		$_ =~ s/[\x{80}-\x{FF}\x{1C}\x{02}\x{05}\x{06}\x{7F}\x{17}\x{10}]//g;
		$_ =~ s/\x{1F}/./g;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$dataLabels{$lN} = $label;
				$lN++;
			}
			$expectedValues = keys %dataLabels;

			print $out $line;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $dataCsv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $dataLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			# p%values;die;

			# Retrieving report data we care about.
			my $vaersId          = $values{'VAERS_ID'}                   // die;
			my $cdcReceptionDate = $values{'RECVDATE'}                   // die;
			my $stateName        = $values{'STATE'}                      // die;
			my $stateInternalId  = $stateName;
			my $patientAge       = $values{'AGE_YRS'}                    // die;
			my ($cdcAgeInternalId,
				$cdcAgeName)     = age_to_age_group($patientAge);
			my $cdcSexInternalId = $values{'SEX'}                            // die;
			my $cdcSexName;
			if ($cdcSexInternalId eq 'F') {
				$cdcSexName = 'Female';
			} elsif ($cdcSexInternalId eq 'M') {
				$cdcSexName = 'Male';
			} elsif ($cdcSexInternalId eq 'U') {
				$cdcSexName = 'Unknown';
			} else {
				die "cdcSexInternalId : $cdcSexInternalId";
			}
			my $vaccinationDate         = $values{'VAX_DATE'};
			my $deceasedDate            = $values{'DATEDIED'};
			my $aEDescription           = $values{'SYMPTOM_TEXT'};
			my $cdcVaccineAdministrator = $values{'V_ADMINBY'};
			$cdcVaccineAdministrator    = administrator_to_enum($cdcVaccineAdministrator);
			my $hospitalized            = $values{'HOSPITAL'};
			my $permanentDisability     = $values{'DISABLE'};
			my $lifeThreatning          = $values{'L_THREAT'};
			my $patientDied             = $values{'DIED'};
			$patientAge                 = undef unless defined $patientAge      && length $patientAge          >= 1;
			$hospitalized               = 0 unless defined $hospitalized        && length $hospitalized        >= 1;
			$permanentDisability        = 0 unless defined $permanentDisability && length $permanentDisability >= 1;
			$lifeThreatning             = 0 unless defined $lifeThreatning      && length $lifeThreatning      >= 1;
			$patientDied                = 0 unless defined $patientDied         && length $patientDied         >= 1;
			$patientDied                = 1 if defined $patientDied             && $patientDied eq 'Y';
			$hospitalized               = 1 if defined $hospitalized            && $hospitalized eq 'Y';
			$permanentDisability        = 1 if defined $permanentDisability     && $permanentDisability eq 'Y';
			$lifeThreatning             = 1 if defined $lifeThreatning          && $lifeThreatning eq 'Y';
		    $cdcReceptionDate           = convert_date($cdcReceptionDate);
			my ($cdcYear) = split '-', $cdcReceptionDate;
		    $vaccinationDate            = convert_date($vaccinationDate) if $vaccinationDate;
		    $deceasedDate               = convert_date($deceasedDate)    if $deceasedDate;
			my $immProjectNumber        = $values{'SPLTTYPE'};
			if ($immProjectNumber =~ /^FR.*$/) {
				$frenchReports++;
				if ($hospitalized || $lifeThreatning || $permanentDisability || $patientDied) {
					$statistics{'byYears'}->{$cdcYear}->{'seriousReports'}++;
				}
				$statistics{'totalReports'}++;
				$statistics{'byYears'}->{$cdcYear}->{'totalReports'}++;
				$frenchReports{$vaersId} = 1;
				print $out $line;
				# say "immProjectNumber        : $immProjectNumber";
				# say "cdcReceptionDate        : $cdcReceptionDate";
				# say "stateName               : $stateName";
				# say "stateInternalId         : $stateInternalId";
				# say "cdcAgeName              : $cdcAgeName";
				# say "patientAge              : $patientAge";
				# say "cdcVaccineAdministrator : $cdcVaccineAdministrator";
				# say "aEDescription           : $aEDescription";
				# say "hospitalized            : $hospitalized";
				# say "permanentDisability     : $permanentDisability";
				# say "lifeThreatning          : $lifeThreatning";
				# say "patientDied             : $patientDied";
				# die "indeed : $immProjectNumber";
			}
		}
	}
	close $dataIn;
	close $out;
	say "frenchReports : $frenchReports";
	# p%statistics;
	# die;

	# Fetching notices - vaccines relations.
	open my $symptomsIn, '<:', $symptomsFile;
	my $symptomsCsv = Text::CSV_XS->new ({ binary => 1 });
	my %symptomsLabels = ();
	$dRNum = 0;
	open my $out2, '>:utf8', $rawSymptOut;
	while (<$symptomsIn>) {
		$dRNum++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s/\r//g;
		$_ =~ s/[\x{80}-\x{FF}\x{1C}\x{02}\x{05}\x{06}\x{7F}\x{17}\x{10}]//g;
		$_ =~ s/\x{1F}/./g;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			print $out2 $line;
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$symptomsLabels{$lN} = $label;
				$lN++;
			}
			$expectedValues = keys %symptomsLabels;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $symptomsCsv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $symptomsLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			my $vaersId  = $values{'VAERS_ID'} // die;
			next unless exists $frenchReports{$vaersId};
			print $out2 $line;
		}
	}
	close $symptomsIn;
	close $out2;

	# Fetching notices - reactions relations.
	open my $vaccinesIn, '<:', $vaccinesFile;
	open my $out3, '>:utf8', $rawVaxOut;
	my $vaccinesCsv = Text::CSV_XS->new ({ binary => 1 });
	my %vaccinesLabels = ();
	$dRNum = 0;
	while (<$vaccinesIn>) {
		$dRNum++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s/\r//g;
		$_ =~ s/[\x{80}-\x{FF}\x{1C}\x{02}\x{05}\x{06}\x{7F}\x{17}\x{10}]//g;
		$_ =~ s/\x{1F}/./g;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			print $out3 $line;
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$vaccinesLabels{$lN} = $label;
				$lN++;
			}
			$expectedValues = keys %vaccinesLabels;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $vaccinesCsv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $vaccinesLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			my $dose    = $values{'VAX_DOSE_SERIES'};
			my $vaersId = $values{'VAERS_ID'} // die;
			next unless exists $frenchReports{$vaersId};
			print $out3 $line;
		}
	}
	close $out3;
	close $vaccinesIn;
}

sub age_to_age_group {
	my ($patientAge) = @_;
	return (0, 'Unknown') unless defined $patientAge && length $patientAge >= 1;
	my ($cdcAgeInternalId, $cdcAgeName);
	if ($patientAge <= 0.16) {
		$cdcAgeInternalId = '1';
		$cdcAgeName       = '0-1 Month';
	} elsif ($patientAge > 0.16 && $patientAge <= 2.9) {
		$cdcAgeInternalId = '2';
		$cdcAgeName = '2 Months - 2 Years';
	} elsif ($patientAge > 2.9 && $patientAge <= 11.9) {
		$cdcAgeInternalId = '3';
		$cdcAgeName = '3-11 Years';
	} elsif ($patientAge > 11.9 && $patientAge <= 17.9) {
		$cdcAgeInternalId = '4';
		$cdcAgeName = '12-17 Years';
	} elsif ($patientAge > 17.9 && $patientAge <= 64.9) {
		$cdcAgeInternalId = '5';
		$cdcAgeName = '18-64 Years';
	} elsif ($patientAge > 64.9 && $patientAge <= 85.9) {
		$cdcAgeInternalId = '6';
		$cdcAgeName = '65-85 Years';
	} elsif ($patientAge > 85.9) {
		$cdcAgeInternalId = '7';
		$cdcAgeName = 'More than 85 Years';
	} else {
		die "patientAge : $patientAge";
	}
	return ($cdcAgeInternalId, $cdcAgeName);
}

sub administrator_to_enum {
	my ($cdcVaccineAdministrator) = @_;
	if ($cdcVaccineAdministrator eq 'MIL') {
		$cdcVaccineAdministrator = 1;
	} elsif ($cdcVaccineAdministrator eq 'OTH') {
		$cdcVaccineAdministrator = 2;
	} elsif ($cdcVaccineAdministrator eq 'PVT') {
		$cdcVaccineAdministrator = 3;
	} elsif ($cdcVaccineAdministrator eq 'PUB') {
		$cdcVaccineAdministrator = 4;
	} elsif ($cdcVaccineAdministrator eq 'UNK') {
		$cdcVaccineAdministrator = 5;
	} elsif ($cdcVaccineAdministrator eq 'PHM') {
		$cdcVaccineAdministrator = 6;
	} elsif ($cdcVaccineAdministrator eq 'WRK') {
		$cdcVaccineAdministrator = 7;
	} elsif ($cdcVaccineAdministrator eq 'SCH') {
		$cdcVaccineAdministrator = 8;
	} elsif ($cdcVaccineAdministrator eq 'SEN') {
		$cdcVaccineAdministrator = 9;
	} else {
		die "cdcVaccineAdministrator : $cdcVaccineAdministrator";
	}
	return $cdcVaccineAdministrator;
}

sub convert_date {
	my ($dt) = @_;
	my ($m, $d, $y) = split "\/", $dt;
	die unless defined $d && defined $m && defined $y;
	return "$y-$m-$d";
}
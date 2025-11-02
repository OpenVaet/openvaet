#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use Text::CSV qw( csv );
use Math::Round qw(nearest);
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Encode;
use Encode::Unicode;
use JSON;
use FindBin;
use Scalar::Util qw(looks_like_number);
use File::stat;
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use time;

# Basic script config.
my $vaers_folder = "raw_data/AllVAERSDataCSVS";        # Where we expect to find CDC's data folder in the project's root folder.

my %years = ();

parse_vaers_years(); # Fetchs years covered.

my %reports_products = ();
my %reports_symptoms = ();

my @reports = ();

parse_us_data();     # Parsing US data from 2020.

open my $out, '>', "data/vaers_reports.json";
print $out encode_json\@reports;
close $out;

sub parse_vaers_years {
	for my $file_path (glob "$vaers_folder/*") {
		(my $file  = $file_path) =~ s/raw_data\/AllVAERSDataCSVS\///;
		next unless $file =~ /^....VAERS.*/;
		my ($year) = $file =~ /(....)/;
		next unless $year >= 2020;
		$years{$year} = 1;
	}
}

sub parse_us_data {
	for my $year (sort{$a <=> $b} keys %years) {
		say "Parsing US - year [$year]";

		# Configuring expected files ; dying if they aren't found.
		my $data_file     = "$vaers_folder/$year" . 'VAERSDATA.csv';
		my $symptoms_file = "$vaers_folder/$year" . 'VAERSSYMPTOMS.csv';
		my $products_file = "$vaers_folder/$year" . 'VAERSVAX.csv';
		die "missing mandatory file for year [$year] in [$vaers_folder]" if !-f $data_file || !-f $symptoms_file || !-f $products_file;
		%reports_products = ();
		%reports_symptoms = ();

		parse_vaers_files(1, $data_file, $symptoms_file, $products_file);
	}
}

sub parse_vaers_files {
	my ($vaers_source, $data_file, $symptoms_file, $products_file) = @_;


	# Fetching notices - products relations.
	open my $products_in, '<:', $products_file;
	my $expected_values;
	my $products_csv = Text::CSV_XS->new ({ binary => 1 });
	my %products_labels = ();
	my $dr_num = 0;
	while (<$products_in>) {
		chomp $_;
		$dr_num++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s// /g;
    	$_ =~ s// /g;
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
		if ($dr_num == 1) {
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$products_labels{$lN} = $label;
				$lN++;
			}
			$expected_values = keys %products_labels;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $products_csv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expected_values" unless scalar @row == $expected_values;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $products_labels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			my $dose     = $values{'VAX_DOSE_SERIES'};
			my $vaers_id = $values{'VAERS_ID'} // die;
			my $manufacturer_name = $values{'VAX_MANU'} // die;
			my $vaccine_type = $values{'VAX_TYPE'} // die;
			my $vaccine_name = $values{"VAX_NAME"} // die;
        	my $drug_name = "$manufacturer_name - $vaccine_type - $vaccine_name";
			my %o = ();
			$o{'manufacturer_name'}      = $manufacturer_name;
			$o{'vaccine_type'} = $vaccine_type;
			$o{'vaccine_name'}         = $vaccine_name;
			$o{'dose'}                   = $dose;
			push @{$reports_products{$vaers_id}->{'products'}}, \%o;
		}
	}
	close $products_in;

	# Fetching notices - symptoms relations.
	open my $symptoms_in, '<:', $symptoms_file;
	my $symptoms_csv = Text::CSV_XS->new ({ binary => 1 });
	my %symptoms_labels = ();
	$dr_num = 0;
	while (<$symptoms_in>) {
		$dr_num++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s// /g;
    	$_ =~ s// /g;
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
		if ($dr_num == 1) {
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$symptoms_labels{$lN} = $label;
				$lN++;
			}
			$expected_values = keys %symptoms_labels;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $symptoms_csv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expected_values" unless scalar @row == $expected_values;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $symptoms_labels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			my $vaers_id  = $values{'VAERS_ID'} // die;
			my $symptom1 = $values{'SYMPTOM1'} // die;
			my $symptom2 = $values{'SYMPTOM2'};
			my $symptom3 = $values{'SYMPTOM3'};
			my $symptom4 = $values{'SYMPTOM4'};
			my $symptom5 = $values{'SYMPTOM5'};
			my @symptoms = ($symptom1, $symptom2, $symptom3, $symptom4, $symptom5);
			for my $symptom_name (@symptoms) {
				next unless $symptom_name && length $symptom_name >= 1;
				$reports_symptoms{$vaers_id}->{$symptom_name} = 1;
			}
		}
	}
	close $symptoms_in;

	# Fetching notices.
	open my $data_in, '<:', $data_file;
	$dr_num = 0;
	my %data_labels = ();
	my $data_csv = Text::CSV_XS->new ({ binary => 1 });
	while (<$data_in>) {
		$dr_num++;

		# Fixing some poor encodings by replacing special chars by their UTF8 equivalents.
		$_ =~ s/–/-/g;
		$_ =~ s/–/-/g;
		$_ =~ s/ –D/ -D/g;
		$_ =~ s/\\xA0//g;
		$_ =~ s/~/--:--/g;
    	$_ =~ s/ / /g;
    	$_ =~ s// /g;
    	$_ =~ s// /g;
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
		if ($dr_num == 1) {
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$data_labels{$lN} = $label;
				$lN++;
			}
			$expected_values = keys %data_labels;
		} else {

			# Verifying we have the expected number of values.
			open my $fh, "<", \$_;
			my $row = $data_csv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expected_values" unless scalar @row == $expected_values;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $data_labels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}

			# Retrieving report data we care about.
			my $vaers_id             = $values{'VAERS_ID'}                  // die;
			# Skipping the report if no Covid vaccine is associated.
			next unless exists $reports_products{$vaers_id};
			my $reception_date  = $values{'RECVDATE'}                  // die;
			my $state_alpha_2            = $values{'STATE'}                     // die;
			my $countryStateId;
			if ($state_alpha_2) {
				$state_alpha_2 = uc $state_alpha_2;
				$state_alpha_2 = 'WA' if $state_alpha_2 eq 'DC';
			}
			my $onset_date           = $values{'ONSET_DATE'};
			my $patient_age          = $values{'AGE_YRS'}                   // die;
			my $sex_id    = $values{'SEX'}                       // die;
			my ($sex_name, $sex);
			if ($sex_id eq 'F') {
				$sex   = 1;
				$sex_name = 'Female';
			} elsif ($sex_id eq 'M') {
				$sex   = 2;
				$sex_name = 'Male';
			} else {
				$sex   = 3;
				$sex_name = 'Unknown';
			}
			my $vaccination_date         = $values{'VAX_DATE'};
			my $deceased_date            = $values{'DATEDIED'};
			my $narrative           = $values{'SYMPTOM_TEXT'};
			my $product_administred_by = $values{'V_ADMINBY'};
			$product_administred_by    = administrator_long_format($product_administred_by);
			my $hospitalized            = $values{'HOSPITAL'};
			my $permanent_disability     = $values{'DISABLE'};
			my $life_threatening          = $values{'L_THREAT'};
			my $spllt_type        = $values{'SPLTTYPE'};
			my $died             = $values{'DIED'};
			$patient_age                 = undef unless defined $patient_age      && length $patient_age          >= 1;
			$hospitalized               = 0 unless defined $hospitalized        && length $hospitalized        >= 1;
			$permanent_disability        = 0 unless defined $permanent_disability && length $permanent_disability >= 1;
			$life_threatening             = 0 unless defined $life_threatening      && length $life_threatening      >= 1;
			$died                = 0 unless defined $died         && length $died         >= 1;
			$died                = 1 if defined $died             && $died eq 'Y';
			$hospitalized               = 1 if defined $hospitalized            && $hospitalized eq 'Y';
			$permanent_disability        = 1 if defined $permanent_disability     && $permanent_disability eq 'Y';
			$life_threatening             = 1 if defined $life_threatening          && $life_threatening eq 'Y';
		    $reception_date         = convert_date($reception_date);
		    $vaccination_date            = convert_date($vaccination_date) if $vaccination_date;
		    $deceased_date               = convert_date($deceased_date)    if $deceased_date;
		    $onset_date                  = convert_date($onset_date)       if $onset_date;
			$onset_date                  = undef unless defined $onset_date       && length $onset_date           >= 1;
			$deceased_date               = undef unless defined $deceased_date    && length $deceased_date        >= 1;
			$vaccination_date            = undef unless defined $vaccination_date && length $vaccination_date     >= 1;
			$patient_age                 = undef unless defined $patient_age      && length $patient_age          >= 1;
			my ($age_group_id,
				$age_group_name);
			if (defined $patient_age) {
				($age_group_id,
					$age_group_name) = age_to_age_group($patient_age);
			}
		    my ($receptionYear, $receptionMonth, $receptionDay) = split '-', $reception_date;
	    	my ($code2, $countryId);
	    	if ($spllt_type && length $spllt_type >= 2) {
		    	($code2) = $spllt_type =~ /^(..).*$/;
	    	}

			# Inserting the report symptoms if unknown.
			my @symptoms_listed     = ();
			for my $symptom_name (sort keys %{$reports_symptoms{$vaers_id}}) {
				my $symptoms_normalized = lc $symptom_name;
				push @symptoms_listed, $symptoms_normalized;
			}

			# Inserting the products data.
			my @products_listed = @{$reports_products{$vaers_id}->{'products'}};

			my %obj = ();
			$obj{'vaers_id'} = $vaers_id;
			$obj{'narrative'} = $narrative;
			$obj{'products_listed'} = \@products_listed;
			$obj{'sex'} = $sex;
			$obj{'product_administred_by'} = $product_administred_by;
			$obj{'patient_age'} = $patient_age;
			$obj{'reception_date'} = $reception_date;
			$obj{'vaccination_date'} = $vaccination_date;
			$obj{'symptoms_listed'} = \@symptoms_listed;
			$obj{'hospitalized'} = $hospitalized;
			$obj{'permanent_disability'} = $permanent_disability;
			$obj{'life_threatening'} = $life_threatening;
			$obj{'died'} = $died;
			$obj{'onset_date'} = $onset_date;
			$obj{'deceased_date'} = $deceased_date;
			$obj{'spllt_type'} = $spllt_type;
			push @reports, \%obj;
		}
	}
	close $data_in;
}

sub age_to_age_group {
	my ($patient_age) = @_;
	return (0, 'Unknown') unless defined $patient_age && length $patient_age >= 1;
	my ($age_group_id, $age_group_name);
	if ($patient_age <= 1.99) {
		$age_group_id = '1';
		$age_group_name       = '<2 Years';
	} elsif ($patient_age >= 2 && $patient_age <= 4.99) {
		$age_group_id = '2';
		$age_group_name = '2 - 4 Years';
	} elsif ($patient_age >= 5 && $patient_age <= 11.99) {
		$age_group_id = '3';
		$age_group_name = '5 - 11 Years';
	} elsif ($patient_age >= 12 && $patient_age <= 17.99) {
		$age_group_id = '4';
		$age_group_name = '12 - 17 Years';
	} elsif ($patient_age >= 18 && $patient_age <= 24.99) {
		$age_group_id = '5';
		$age_group_name = '18 - 24 Years';
	} elsif ($patient_age >= 25 && $patient_age <= 49.99) {
		$age_group_id = '6';
		$age_group_name = '25 - 49 Years';
	} elsif ($patient_age >= 50 && $patient_age <= 64.99) {
		$age_group_id = '6';
		$age_group_name = '50 - 64 Years';
	} elsif ($patient_age >= 65) {
		$age_group_id = '7';
		$age_group_name = '65+ Years';
	} else {
		die "patient_age : $patient_age";
	}
	return ($age_group_id, $age_group_name);
}

sub administrator_long_format {
	my ($product_administred_by) = @_;
	if ($product_administred_by eq 'MIL') {
		$product_administred_by = "Military";
	} elsif ($product_administred_by eq 'OTH') {
		$product_administred_by = "Other";
	} elsif ($product_administred_by eq 'PVT') {
		$product_administred_by = "Private";
	} elsif ($product_administred_by eq 'PUB') {
		$product_administred_by = "Public";
	} elsif ($product_administred_by eq 'UNK') {
		$product_administred_by = "Unknown";
	} elsif ($product_administred_by eq 'PHM') {
		$product_administred_by = "Pharmacy";
	} elsif ($product_administred_by eq 'WRK') {
		$product_administred_by = "Work";
	} elsif ($product_administred_by eq 'SCH') {
		$product_administred_by = "School";
	} elsif ($product_administred_by eq 'SEN') {
		$product_administred_by = "Senior Living";
	} else {
		die "product_administred_by : $product_administred_by";
	}
	return $product_administred_by;
}

sub convert_date {
	my ($dt) = @_;
	my ($m, $d, $y) = split "\/", $dt;
	die unless defined $d && defined $m && defined $y;
	return "$y-$m-$d";
}
#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
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
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use config;
use global;
use time;

# https://api.census.gov/data.html

# Basic script config.
my $statesFile       = "tasks/cdc/states.csv";             # File containing CDC's states.
my $cdcFolder        = "raw_data/AllVAERSDataCSVS";        # Where we expect to find CDC's data folder in the project's root folder.
my $vaccinationFile  = 'raw_data/COVID-19_Vaccination_and_Case_Trends_by_Age_Group__United_States.csv'; # File containing the current vaccination statistics by age groups,
																										# taken from https://data.cdc.gov/api/views/gxj9-t96f/rows.csv?accessType=DOWNLOAD&bom=true&format=true&delimiter=%3B
my $populationFile   = 'raw_data/nc-est2021-syasexn.csv';  # File containing "Annual Estimates of the Resident Population by Single Year of Age and Sex for the United States: April 1, 2020 to July 1, 2021"
														   # taken from https://www2.census.gov/programs-surveys/popest/tables/2020-2021/national/asrh/nc-est2021-syasexn.xlsx
														   # and converted to UTF8 ";" separated .CSV
my $cdcForeignFolder = "raw_data/NonDomesticVAERSData";    # Where we expect to find CDC's data folder in the project's root folder.

# Loading flagged symptoms.
my $latestSymptomId = 0;
my %ausSymptoms = ();
aus_symptom();

# Loading population data.
my %populationByAges = ();
my %populationByAgeGroups = ();
load_population_age();

# Preparing age for vaccination's age groups.
my %ageGroups = ();
set_age_groups();
prepare_population_by_age_group();

# Loading vaccination data.
my %dosesByDates = ();
load_vaccination_data();

# Verifying in current .ZIP file if things have been deleted.
my %years = ();
my %statesCodes = ();
parse_states();
parse_cdc_years();
my %reportsByDates = ();
my %symptomsMet = ();
my $totalReports = 0;
my %stats = ();
# parse_foreign_data();
parse_yearly_data();
p%stats;

# Printing dates & other stats.
open my $out, '>:utf8', 'vax_by_doses.csv';
for my $lastProductTaken (sort keys %stats) {
	for my $lastDoseTaken (sort keys %{$stats{$lastProductTaken}}) {
		my $totalDeaths = $stats{$lastProductTaken}->{$lastDoseTaken}->{'totalDeaths'} // die;
		say $out "$lastProductTaken;$lastDoseTaken;$totalDeaths;";
	}
}
close $out;

# Printing symptoms encountered.
# open my $out2, '>:utf8', 'symptoms.csv';
for my $ausSymptomName (sort keys %symptomsMet) {
	my $timesSeen = $symptomsMet{$ausSymptomName}->{'timesSeen'} // die;
	unless (exists $ausSymptoms{$ausSymptomName}->{'ausSymptomId'}) {
		my $sth = $dbh->prepare("INSERT INTO aus_symptom (name, timeSeen) VALUES (?, ?)");
		$sth->execute($ausSymptomName, $timesSeen) or die $sth->err();
	}
	# say "symptomName : $symptomName";
	# say "timesSeen : $timesSeen";
	# say $out2 "$symptomName;$timesSeen;";
}
# close $out2;

sub aus_symptom {
	my $tb = $dbh->selectall_hashref("SELECT id as ausSymptomId, name as ausSymptomName, active FROM aus_symptom WHERE id > $latestSymptomId", 'ausSymptomId');
	for my $ausSymptomId (sort{$a <=> $b} keys %$tb) {
		$latestSymptomId = $ausSymptomId;
		my $ausSymptomName = %$tb{$ausSymptomId}->{'ausSymptomName'} // die;
		my $active         = %$tb{$ausSymptomId}->{'active'}         // die;
		$active            = unpack("N", pack("B32", substr("0" x 32 . $active, -32)));
		$ausSymptoms{$ausSymptomName}->{'ausSymptomId'} = $ausSymptomId;
		$ausSymptoms{$ausSymptomName}->{'active'} = $active;
	}
}

sub load_population_age {
	open my $in, '<:utf8', $populationFile;
	my $agesLoaded = 0;
	while (<$in>) {
		chomp $_;
		my ($age, $april20Population, $july20Population, $july21Population) = split ';', $_;
		next unless $age && $july21Population;
		next unless $age =~ /\..*/;
		$age =~ s/\.//;
		$age =~ s/\+//;
		$agesLoaded++;
		$july20Population =~ s/ //g;
		$july21Population =~ s/ //g;
		$populationByAges{$age}->{'july20Population'} = $july20Population;
		$populationByAges{$age}->{'july21Population'} = $july21Population;
		last if $agesLoaded == 101;
	}
	close $in;
}

sub set_age_groups {
	$ageGroups{'1'}->{'label'}  = '<2 Years';
	$ageGroups{'1'}->{'from'}   = '0';
	$ageGroups{'1'}->{'to'}     = '1';
	$ageGroups{'2'}->{'label'}  = '2 - 4 Years';
	$ageGroups{'2'}->{'from'}   = '2';
	$ageGroups{'2'}->{'to'}     = '4';
	$ageGroups{'3'}->{'label'}  = '5 - 11 Years';
	$ageGroups{'3'}->{'from'}   = '5';
	$ageGroups{'3'}->{'to'}     = '11';
	$ageGroups{'4'}->{'label'}  = '12 - 17 Years';
	$ageGroups{'4'}->{'from'}   = '12';
	$ageGroups{'4'}->{'to'}     = '17';
}

sub prepare_population_by_age_group {
	for my $aNum (sort{$a <=> $b} keys %ageGroups) {
		my $label = $ageGroups{$aNum}->{'label'} // die;
		my $from  = $ageGroups{$aNum}->{'from'}  // die;
		my $to    = $ageGroups{$aNum}->{'to'}    // die;
		my ($july20Population, $july21Population) = (0, 0);
		for my $age (sort{$a <=> $b} keys %populationByAges) {
			next if $age < $from;
			next if $age > $to;
			my $july20 = $populationByAges{$age}->{'july20Population'} // die;
			my $july21 = $populationByAges{$age}->{'july21Population'} // die;
			$july20Population += $july20;
			$july21Population += $july21;
		}
		$populationByAgeGroups{$label}->{'july20Population'} = $july20Population;
		$populationByAgeGroups{$label}->{'july21Population'} = $july21Population;
	}
}

sub load_vaccination_data {
	my ($highestDate, $lowestDate) = (0, 99999999);
	my %vaccinesByAgeGroups = ();
	open my $in, '<:utf8', $vaccinationFile;
	my $agesLoaded = 0;
	while (<$in>) {
		chomp $_;
		my ($date, $ageGroup, $casePer100K, $dose1Percent, $dose2Percent) = split ';', $_;
		my ($month, $day, $year) = $date =~ /(..)\/(..)\/(....)/;
		next unless $month && $day && $year;
		$date = "$year-$month-$day";
		my $compDate = $date;
		$compDate =~ s/\D//g;
		$highestDate = $compDate if $compDate > $highestDate;
		$lowestDate  = $compDate if $compDate < $lowestDate;
		my $referenceYear;
		if ($year eq '2022' || $year eq '2021') {
			$referenceYear = '21';
		} elsif ($year eq '2020') {
			$referenceYear = '20';
		} else {
			die "year : $year";
		}
		my $population = $populationByAgeGroups{$ageGroup}->{"july$referenceYear" . "Population"} // next;
		my $doses1Administered = nearest(1, $population * $dose1Percent / 100);
		my $doses2Administered = nearest(1, $population * $dose2Percent / 100);
		next unless $doses1Administered || $doses2Administered;
		$dosesByDates{$date}->{'weekNumber'} = iso_week_number("$year-$month-$day");
		$dosesByDates{$date}->{'doses1Administered'} += $doses1Administered;
		$dosesByDates{$date}->{'doses2Administered'} += $doses2Administered;
	}
	close $in;
	my ($hY, $hM, $hD) = $highestDate =~ /(....)(..)(..)/;
	my ($lY, $lM, $lD) = $lowestDate  =~ /(....)(..)(..)/;
	$highestDate = "$hY-$hM-$hD";
	$lowestDate  = "$lY-$lM-$lD";
	delete $dosesByDates{$highestDate}; # The latest date is often truncated (having only a few age groups we care about), therefore deleted.
}

sub parse_states {
	open my $in, '<:utf8', $statesFile;
	while (<$in>) {
		chomp $_;
		my ($sNum, $sCode2, $sName) = split ';', $_;
		die if exists $statesCodes{$sCode2};
		$statesCodes{$sCode2}->{'stateName'}  = $sName;
		$statesCodes{$sCode2}->{'internalId'} = $sNum;
	}
	close $in;
}

sub parse_cdc_years {
	for my $filePath (glob "$cdcFolder/*") {
		(my $file  = $filePath) =~ s/raw_data\/AllVAERSDataCSVS\///;
		next unless $file =~ /^....VAERS.*/;
		my ($year) = $file =~ /(....)/; 
		$years{$year} = 1;
	}
}

sub parse_yearly_data {
	for my $year (sort{$a <=> $b} keys %years) {
		next unless $year > 2018;

		# Configuring expected files ; dying if they aren't found.
		my $dataFile     = "$cdcFolder/$year" . 'VAERSDATA.csv';
		my $symptomsFile = "$cdcFolder/$year" . 'VAERSSYMPTOMS.csv';
		my $vaccinesFile = "$cdcFolder/$year" . 'VAERSVAX.csv';
		die "missing mandatory file for year [$year] in [$cdcFolder]" if !-f $dataFile || !-f $symptomsFile || !-f $vaccinesFile;
		say "dataFile     : $dataFile";
		say "symptomsFile : $symptomsFile";
		say "vaccinesFile : $vaccinesFile";
		say "year         : $year";

		# Fetching notices - vaccines relations.
		open my $vaccinesIn, '<:', $vaccinesFile;
		my $expectedValues;
		my $vaccinesCsv = Text::CSV_XS->new ({ binary => 1 });
		my %vaccinesLabels = ();
		my %reportsVaccines = ();
		my $dRNum = 0;
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
				my $cdcReportInternalId = $values{'VAERS_ID'} // die;
				my $cdcManufacturerName = $values{'VAX_MANU'} // die;
				my $cdcVaccineTypeName = $values{'VAX_TYPE'} // die;
				my $cdcVaccineLotNumber = $values{'VAX_LOT'} // die;
				my $cdcVaccineName = $values{"VAX_NAME\n"} // die;
	        	my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";

	        	# We verify here that the vaccine is indeed related to a COVID one.
	        	my ($substanceCategory, $substanceShortenedName) = substance_synthesis($drugName);
	        	next unless $substanceCategory && $substanceCategory eq 'COVID-19';
	        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE PFIZER-BIONTECH';
	        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE MODERNA';
	        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE JANSSEN';
				my %o = ();
				$o{'substanceCategory'} = $substanceCategory;
				$o{'substanceShortenedName'} = $substanceShortenedName;
				$o{'cdcVaccineName'} = $cdcVaccineName;
				$o{'lotNumber'} = $cdcVaccineLotNumber;
				$o{'dose'} = $dose;
				push @{$reportsVaccines{$cdcReportInternalId}->{'vaccines'}}, \%o;
			}
		}
		close $vaccinesIn;

		# Fetching notices - symptoms relations.
		open my $symptomsIn, '<:', $symptomsFile;
		my $symptomsCsv = Text::CSV_XS->new ({ binary => 1 });
		my %symptomsLabels = ();
		$dRNum = 0;
		my %reportsSymptoms = ();
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
				my $cdcReportInternalId  = $values{'VAERS_ID'} // die;
				my $symptom1 = $values{'SYMPTOM1'} // die;
				my $symptom2 = $values{'SYMPTOM2'};
				my $symptom3 = $values{'SYMPTOM3'};
				my $symptom4 = $values{'SYMPTOM4'};
				my $symptom5 = $values{'SYMPTOM5'};
				my @symptoms = ($symptom1, $symptom2, $symptom3, $symptom4, $symptom5);
				next unless exists $reportsVaccines{$cdcReportInternalId}->{'vaccines'};
				for my $symptomName (@symptoms) {
					next unless $symptomName && length $symptomName >= 1;
					$reportsSymptoms{$cdcReportInternalId}->{$symptomName} = 1;
				}
			}
		}
		close $symptomsIn;

		# Fetching notices.
		my $definedAge = 0;
		open my $dataIn, '<:', $dataFile;
		$dRNum = 0;
		my %dataLabels = ();
		my $dataCsv = Text::CSV_XS->new ({ binary => 1 });
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

				# Retrieving report data we care about.
				my $cdcReportInternalId = $values{'VAERS_ID'}                  // die;
				my $cdcReceptionDate    = $values{'RECVDATE'}                  // die;
				my $sCode2              = $values{'STATE'}                     // die;
				$sCode2                 = $statesCodes{$sCode2}->{'stateName'} // $sCode2;
				my $patientAge          = $values{'AGE_YRS'}                   // die;
				my $cdcSexInternalId    = $values{'SEX'}                       // die;
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
				$cdcVaccineAdministrator    = administrator_to_litteral($cdcVaccineAdministrator);
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
			    $vaccinationDate            = convert_date($vaccinationDate) if $vaccinationDate;
			    $deceasedDate               = convert_date($deceasedDate)    if $deceasedDate;
			    my ($receptionYear, $receptionMonth, $receptionDay) = split '-', $cdcReceptionDate;
			    my $compDate = "$receptionYear$receptionMonth$receptionDay";
				my $immProjectNumber        = $values{'SPLTTYPE'};

				# Taking care of building stats.
				next unless exists $reportsVaccines{$cdcReportInternalId}->{'vaccines'};

				my %o = ();
				$o{'cdcReportInternalId'} = $cdcReportInternalId;
				$o{'cdcReceptionDate'} = $cdcReceptionDate;
				$o{'sCode2'}          = $sCode2;
				$o{'source'}          = 'usa';
				$o{'patientAge'}      = $patientAge;
				$o{'cdcSexInternalId'} = $cdcSexInternalId;
				$o{'cdcSexName'}      = $cdcSexName;
				$o{'vaccinationDate'} = $vaccinationDate;
				$o{'deceasedDate'}    = $deceasedDate;
				$o{'aEDescription'} = $aEDescription;
				$o{'cdcVaccineAdministrator'} = $cdcVaccineAdministrator;
				$o{'hospitalized'}    = $hospitalized;
				$o{'permanentDisability'} = $permanentDisability;
				$o{'lifeThreatning'}  = $lifeThreatning;
				$o{'patientDied'} = $patientDied;
				$o{'immProjectNumber'} = $immProjectNumber;
				for my $ausSymptomName (sort keys %{$reportsSymptoms{$cdcReportInternalId}}) {
					$o{'symptoms'}->{$ausSymptomName} = 1;
				}
				my ($lastProductTaken, $lastDoseTaken);
				for my $vaccData (@{$reportsVaccines{$cdcReportInternalId}->{'vaccines'}}) {
					my $dose                   = %$vaccData{'dose'}                   // die;
					my $substanceShortenedName = %$vaccData{'substanceShortenedName'} // die;
					$lastProductTaken = $substanceShortenedName;
					$lastDoseTaken    = $dose;
					push @{$o{'vaccines'}}, \%$vaccData;
				}
				die unless $lastProductTaken;
				if ($patientDied) {
					$stats{$lastProductTaken}->{$lastDoseTaken}->{'totalDeaths'}++;
				}
				$totalReports++;
				push @{$reportsByDates{$compDate}}, \%o;
			}
		}
		close $dataIn;
		say "totalReports : $totalReports";
		say "definedAge : $definedAge";

	}
}

sub administrator_to_litteral {
	my ($cdcVaccineAdministrator) = @_;
	if ($cdcVaccineAdministrator eq 'MIL') {
		$cdcVaccineAdministrator = "Military";
	} elsif ($cdcVaccineAdministrator eq 'OTH') {
		$cdcVaccineAdministrator = "Other";
	} elsif ($cdcVaccineAdministrator eq 'PVT') {
		$cdcVaccineAdministrator = "Private";
	} elsif ($cdcVaccineAdministrator eq 'PUB') {
		$cdcVaccineAdministrator = "Public";
	} elsif ($cdcVaccineAdministrator eq 'UNK') {
		$cdcVaccineAdministrator = "Unknown";
	} elsif ($cdcVaccineAdministrator eq 'PHM') {
		$cdcVaccineAdministrator = "Pharmacy";
	} elsif ($cdcVaccineAdministrator eq 'WRK') {
		$cdcVaccineAdministrator = "Work";
	} elsif ($cdcVaccineAdministrator eq 'SCH') {
		$cdcVaccineAdministrator = "School";
	} elsif ($cdcVaccineAdministrator eq 'SEN') {
		$cdcVaccineAdministrator = "Senior Living";
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

sub substance_synthesis {
    my ($substanceName) = @_;
    return 0 if
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLULAVAL QUADRIVALENT)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - RV1 - ROTAVIRUS (ROTARIX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - MENB - MENINGOCOCCAL B (BEXSERO)' ||
        $substanceName eq 'MERCK & CO. INC. - HIBV - HIB (PEDVAXHIB)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - MNQ - MENINGOCOCCAL CONJUGATE (MENVEO)' ||
        $substanceName eq 'BERNA BIOTECH, LTD - TYP - TYPHOID LIVE ORAL TY21A (VIVOTIF)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HIBV - HIB (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'AVENTIS PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - MENHIB - MENINGOCOCCAL CONJUGATE + HIB (MENITORIX)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLUA3 - INFLUENZA (SEASONAL) (FLUAD)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - RVX - ROTAVIRUS (NO BRAND NAME)' ||
        $substanceName eq 'MERCK & CO. INC. - RV5 - ROTAVIRUS (ROTATEQ)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HPV2 - HPV (CERVARIX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - MMR - MEASLES + MUMPS + RUBELLA (PRIORIX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - VARCEL - VARICELLA (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE QUADRIVALENT)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - PPV - PNEUMO (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - PNC10 - PNEUMO (SYNFLORIX)' ||
        $substanceName eq 'MERCK & CO. INC. - VARCEL - VARICELLA (VARIVAX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (GSK))' ||
        $substanceName eq 'MERCK & CO. INC. - HEPA - HEP A (VAQTA)' ||
        $substanceName eq 'MASS. PUB HLTH BIOL LAB - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HEPATYP - HEP A + TYP (HEPATYRIX)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE)' ||
        $substanceName eq 'MERCK & CO. INC. - PPV - PNEUMO (PNEUMOVAX)' ||
        $substanceName eq 'MEDEVA PHARMA, LTD. - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'SANOFI PASTEUR - BCG - BCG (MYCOBAX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - LYME - LYME (LYMERIX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (TIV DRESDEN)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLULAVAL)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (QIV QUEBEC)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (QIV DRESDEN)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLUARIX)' ||
        $substanceName eq 'PROTEIN SCIENCES CORPORATION - FLUR4 - INFLUENZA (SEASONAL) (FLUBLOK QUADRIVALENT)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (OTHER)' ||
        $substanceName eq 'PFIZER\WYETH - MENB - MENINGOCOCCAL B (TRUMENBA)' ||
        $substanceName eq 'MERCK & CO. INC. - MMRV - MEASLES + MUMPS + RUBELLA + VARICELLA (PROQUAD)' ||
        $substanceName eq 'MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (MMR II)' ||
        $substanceName eq 'SEQIRUS, INC. - FLUC4 - INFLUENZA (SEASONAL) (FLUCELVAX QUADRIVALENT)' ||
        $substanceName eq 'MERCK & CO. INC. - HPV9 - HPV (GARDASIL 9)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - VARZOS - ZOSTER (SHINGRIX)' ||
        $substanceName eq 'PAXVAX - CHOL - CHOLERA (VAXCHORA)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - LYME - LYME (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MU - MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - VARZOS - ZOSTER (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - HIBV - HIB (ACTHIB)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - MNQHIB - MENINGOCOCCAL C & Y + HIB (MENHIBRIX)' ||
        $substanceName eq 'PFIZER\WYETH - PNC - PNEUMO (PREVNAR)' ||
        $substanceName eq 'SANOFI PASTEUR - TYP - TYPHOID VI POLYSACCHARIDE (TYPHIM VI)' ||
        $substanceName eq 'MERCK & CO. INC. - VARZOS - ZOSTER LIVE (ZOSTAVAX)' ||
        $substanceName eq 'MERCK & CO. INC. - RUB - RUBELLA (MERUVAX II)' ||
        $substanceName eq 'PFIZER\WYETH - PNC13 - PNEUMO (PREVNAR13)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'MERCK & CO. INC. - HPV4 - HPV (GARDASIL)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - RUB - RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MEN - MENINGOCOCCAL (NO BRAND NAME)' ||
        $substanceName eq 'SEQIRUS, INC. - FLUA4 - INFLUENZA (SEASONAL) (FLUAD QUADRIVALENT)' ||
        $substanceName eq 'PFIZER\WYETH - PNC20 - PNEUMO (PREVNAR20)' ||
        $substanceName eq 'LEDERLE PRAXSIS - HIBV - HIB POLYSACCHARIDE (FOREIGN)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - SMALL - SMALLPOX (NO BRAND NAME)' ||
        $substanceName eq 'MEDIMMUNE VACCINES, INC. - FLUN(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (MEDIMMUNE))' ||
        $substanceName eq 'MEDIMMUNE VACCINES, INC. - FLUN3 - INFLUENZA (SEASONAL) (FLUENZ)' ||
        $substanceName eq 'MEDIMMUNE VACCINES, INC. - FLUN4 - INFLUENZA (SEASONAL) (FLUENZ TETRA)' ||
        $substanceName eq 'MERCK & CO. INC. - EBZR - EBOLA ZAIRE (ERVEBO)' ||
        $substanceName eq 'MERCK & CO. INC. - MEA - MEASLES (ATTENUVAX)' ||
        $substanceName eq 'MERCK & CO. INC. - MEA - MEASLES (FOREIGN)' ||
        $substanceName eq 'MERCK & CO. INC. - MEA - MEASLES (NO BRAND NAME)' ||
        $substanceName eq 'MERCK & CO. INC. - MER - MEASLES + RUBELLA (MR-VAX II)' ||
        $substanceName eq 'MERCK & CO. INC. - MM - MEASLES + MUMPS (MM-VAX)' ||
        $substanceName eq 'MERCK & CO. INC. - MM - MEASLES + MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (MMR I)' ||
        $substanceName eq 'MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (VIRIVAC)' ||
        $substanceName eq 'MERCK & CO. INC. - MU - MUMPS (MUMPSVAX I)' ||
        $substanceName eq 'MERCK & CO. INC. - MU - MUMPS (MUMPSVAX II)' ||
        $substanceName eq 'MERCK & CO. INC. - MUR - MUMPS + RUBELLA (FOREIGN)' ||
        $substanceName eq 'MERCK & CO. INC. - PNC15 - PNEUMO (VAXNEUVANCE)' ||
        $substanceName eq 'MERCK & CO. INC. - RUB - RUBELLA (MERUVAX I)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLUA3 - INFLUENZA (SEASONAL) (CHIROMAS)' ||
        $substanceName eq 'BERNA BIOTECH, LTD. - MEA - MEASLES (MORATEN)' ||
        $substanceName eq 'PFIZER\WYETH - TBE - TICK-BORNE ENCEPH (TICOVAC)' ||
        $substanceName eq 'MEDEVA PHARMA, LTD. - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (ENZIRA)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (TIV QUEBEC)' ||
        $substanceName eq 'CSL LIMITED - FLUX - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'MERCK & CO. INC. - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - ANTH - ANTHRAX (NO BRAND NAME)' ||
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'MILES LABORATORIES - PLAGUE - PLAGUE (NO BRAND NAME)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (NOVARTIS))' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLU3 - INFLUENZA (SEASONAL) (AGRIFLU)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLUC3 - INFLUENZA (SEASONAL) (OPTAFLU)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLUX - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABIVAC)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABIPUR)' ||
        $substanceName eq 'ORGANON-TEKNIKA - BCG - BCG (TICE)' ||
        $substanceName eq 'PARKDALE PHARMACEUTICALS - FLU3 - INFLUENZA (SEASONAL) (FLUOGEN)' ||
        $substanceName eq 'PARKE-DAVIS - FLU3 - INFLUENZA (SEASONAL) (FLUOGEN)' ||
        $substanceName eq 'PASTEUR MERIEUX INST. - RAB - RABIES (IMOVAX ID)' ||
        $substanceName eq 'PASTEUR MERIEUX INST. - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'PFIZER\WYETH - ADEN - ADENOVIRUS (TYPE 4, NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - ADEN - ADENOVIRUS (TYPE 7, NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - CHOL - CHOLERA (USP)' ||
        $substanceName eq 'PFIZER\WYETH - FLU3 - INFLUENZA (SEASONAL) (FLU-IMUNE)' ||
        $substanceName eq 'PFIZER\WYETH - FLU3 - INFLUENZA (SEASONAL) (FLUSHIELD)' ||
        $substanceName eq 'PFIZER\WYETH - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - HBPV - HIB POLYSACCHARIDE (HIBIMUNE)' ||
        $substanceName eq 'PFIZER\WYETH - HIBV - HIB (HIBTITER)' ||
        $substanceName eq 'PFIZER\WYETH - MNC - MENINGOCOCCAL (MENINGITEC)' ||
        $substanceName eq 'PFIZER\WYETH - PPV - PNEUMO (PNU-IMUNE)' ||
        $substanceName eq 'PFIZER\WYETH - RV - ROTAVIRUS (ROTASHIELD)' ||
        $substanceName eq 'PFIZER\WYETH - SMALL - SMALLPOX (DRYVAX)' ||
        $substanceName eq 'PFIZER\WYETH - TYP - TYPHOID VI POLYSACCHARIDE (ACETONE INACTIVATED DRIED)' ||
        $substanceName eq 'PFIZER\WYETH - TYP - TYPHOID VI POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'PROTEIN SCIENCES CORPORATION - FLUR3 - INFLUENZA (SEASONAL) (FLUBLOK)' ||
        $substanceName eq 'SANOFI PASTEUR - DF - DENGUE TETRAVALENT (DENGVAXIA)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (SANOFI))' ||
        $substanceName eq 'SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE INTRADERMAL)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE INTRADERMAL QUADRIVALENT)' ||
        $substanceName eq 'SANOFI PASTEUR - H5N1 - INFLUENZA (SEASONAL) (PANDEMIC FLU VACCINE (H5N1))' ||
        $substanceName eq 'SANOFI PASTEUR - HIBV - HIB (OMNIHIB)' ||
        $substanceName eq 'SANOFI PASTEUR - HIBV - HIB (PROHIBIT)' ||
        $substanceName eq 'SANOFI PASTEUR - HIBV - HIB (TETRACOQ)' ||
        $substanceName eq 'SANOFI PASTEUR - JEV - JAPANESE ENCEPHALITIS (JE-VAX)' ||
        $substanceName eq 'SANOFI PASTEUR - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'SANOFI PASTEUR - RAB - RABIES (RABIE-VAX)' ||
        $substanceName eq 'SANOFI PASTEUR - RUB - RUBELLA (RUDIVAX)' ||
        $substanceName eq 'SANOFI PASTEUR - YF - YELLOW FEVER (STAMARIL)' ||
        $substanceName eq 'SMITHKLINE BEECHAM - HEPA - HEP A (HAVRIX)' ||
        $substanceName eq 'SMITHKLINE BEECHAM - LYME - LYME (LYMERIX)' ||
        $substanceName eq 'TEVA PHARMACEUTICALS - ADEN_4_7 - ADENOVIRUS TYPES 4 & 7, LIVE, ORAL (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - ADEN - ADENOVIRUS (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - ANTH - ANTHRAX (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - BCG - BCG (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - CEE - FSME-IMMUN. (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - CHOL - CHOLERA (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MEA - MEASLES (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MENHIB - MENINGOCOCCAL CONJUGATE + HIB (UNKNOWN)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MER - MEASLES + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MM - MEASLES + MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MMRV - MEASLES + MUMPS + RUBELLA + VARICELLA (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MNQ - MENINGOCOCCAL CONJUGATE (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MUR - MUMPS + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - PER - PERTUSSIS (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - PLAGUE - PLAGUE (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - SSEV - SUMMER/SPRING ENCEPH (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TBE - TICK-BORNE ENCEPH (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TYP - TYPHOID LIVE ORAL TY21A (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TYP - TYPHOID VI POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (FOREIGN)' ||
        $substanceName eq 'GREER LABORATORIES, INC. - PLAGUE - PLAGUE (USP)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - JEVX - JAPANESE ENCEPHALITIS (NO BRAND NAME)' ||
        $substanceName eq 'LEDERLE LABORATORIES - CHOL - CHOLERA (USP)' ||
        $substanceName eq 'SANOFI PASTEUR - YF - YELLOW FEVER (YF-VAX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HPVX - HPV (NO BRAND NAME)' ||
        $substanceName eq 'MEDIMMUNE VACCINES, INC. - FLUN4 - INFLUENZA (SEASONAL) (FLUMIST QUADRIVALENT)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABAVERT)' ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - FLUC3 - INFLUENZA (SEASONAL) (FLUCELVAX)' ||
        $substanceName eq 'BERNA BIOTECH, LTD. - TYP - TYPHOID LIVE ORAL TY21A (VIVOTIF)' ||
        $substanceName eq 'BURROUGHS WELLCOME - RUB - RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - VARCEL - VARICELLA (VARILRIX)' ||
        $substanceName eq 'INTERCELL AG - JEV1 - JAPANESE ENCEPHALITIS (IXIARO)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - FLUX(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (UNKNOWN))' ||
        $substanceName eq 'MEDIMMUNE VACCINES, INC. - FLUN3 - INFLUENZA (SEASONAL) (FLUMIST)' ||
        $substanceName eq 'CONNAUGHT LTD. - RAB - RABIES (IMOVAX)' ||
        $substanceName eq 'SANOFI PASTEUR - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HEPA - HEP A (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - JEV - JAPANESE ENCEPHALITIS (J-VAX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HEPA - HEP A (HAVRIX)' ||
        $substanceName eq 'SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENACTRA)' ||
        $substanceName eq 'CSL LIMITED - FLU(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (CSL))' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - YF - YELLOW FEVER (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LTD. - MEN - MENINGOCOCCAL (MENOMUNE-A/C)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - MMR - MEASLES + MUMPS + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - PER - PERTUSSIS (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - MEN - MENINGOCOCCAL (MENOMUNE)' ||
        $substanceName eq 'SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENQUADFI)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - RAB - RABIES (NO BRAND NAME)' ||
        $substanceName eq 'SEQIRUS, INC. - FLU4 - INFLUENZA (SEASONAL) (AFLURIA QUADRIVALENT)' ||
        $substanceName eq 'SANOFI PASTEUR - SMALL - SMALLPOX (ACAM2000)' ||
        $substanceName eq 'LEDERLE LABORATORIES - FLU3 - INFLUENZA (SEASONAL) (FLU-IMUNE)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - YF - YELLOW FEVER (YF-VAX)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - TYP - TYPHOID VI POLYSACCHARIDE (TYPHIM VI)' ||
        $substanceName eq 'EVANS VACCINES - FLU3 - INFLUENZA (SEASONAL) (FLUVIRIN)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - MEN - MENINGOCOCCAL (MENOMUNE)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - ANTH - ANTHRAX (BIOTHRAX)' ||
        $substanceName eq 'CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (AFLURIA)' ||
        $substanceName eq 'CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (FLUVAX)' ||
        $substanceName eq 'CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (NILGRIP)' ||
        $substanceName eq 'CSL LIMITED - FLU3 - INFLUENZA (SEASONAL) (FOREIGN)' ||
        $substanceName eq 'SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE QUADRIVALENT)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLUARIX QUADRIVALENT)' ||
        $substanceName eq 'BAVARIAN NORDIC - SMALLMNK - SMALLPOX + MONKEYPOX (JYNNEOS)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - SMALL - SMALLPOX (ACAM2000)';
    my $substanceShortenedName;
    if (
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HIBV - HIB (HIBERIX)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - HIBV - HIB (ACTHIB)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - HIBV - HIB (PROHIBIT)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HBPV - HIB POLYSACCHARIDE (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - HEP - HEP B (GENHEVAC B)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HEP - HEPBC (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'SANOFI PASTEUR - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'SCLAVO - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DT - DT ADSORBED (DITANRIX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTOX - DIPHTHERIA TOXOIDS (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LTD. - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'BSI - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'LEDERLE LABORATORIES - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MASS. PUB HLTH BIOL LAB - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - DT - DT ADSORBED (DECAVAC)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DT - DT ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA VACCINE';
    } elsif (
        $substanceName eq 'PASTEUR MERIEUX CONNAUGHT - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (IPOL)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (POLIOVAX)' ||
        $substanceName eq 'PASTEUR MERIEUX INST. - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - OPV - POLIO VIRUS, ORAL (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (IPV) VACCINE';
    } elsif (
        $substanceName eq 'UNKNOWN MANUFACTURER - OPV - POLIO VIRUS, ORAL (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - OPV - POLIO VIRUS, ORAL (ORIMUNE)' ||
        $substanceName eq 'CONNAUGHT LTD. - IPV - POLIO VIRUS, INACT. (POLIOVAX)'
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (OPV) VACCINE';
    } elsif (
        $substanceName eq 'UNKNOWN MANUFACTURER - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'BERNA BIOTECH, LTD. - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - TTOX - TETANUS TOXOID (TEVAX)' ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'LEDERLE LABORATORIES - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'LEDERLE LABORATORIES - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MASS. PUB HLTH BIOL LAB - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MEDEVA PHARMA, LTD. - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'SCLAVO - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq 'SCLAVO - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'TETANUS VACCINE';
    } elsif (
        $substanceName eq 'MERCK & CO. INC. - HBHEPB - HIB + HEP B (COMVAX)' ||
        $substanceName eq 'MERCK & CO. INC. - HEP - HEP B (FOREIGN)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HBHEPB - HIB + HEP B (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'HAEMOPHILIUS B & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'UNKNOWN MANUFACTURER - HEPAB - HEP A + HEP B (NO BRAND NAME)' ||
        $substanceName eq 'DYNAVAX TECHNOLOGIES CORPORATION - HEP - HEP B (HEPLISAV-B)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'MERCK & CO. INC. - HEP - HEP B (RECOMBIVAX HB)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - HEP - HEP B (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - HEPAB - HEP A + HEP B (TWINRIX)' ||
        $substanceName eq 'SMITHKLINE BEECHAM - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'SMITHKLINE BEECHAM - HEPAB - HEP A + HEP B (TWINRIX)'
    ) {
        $substanceShortenedName = 'HEPATITE A & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'SANOFI PASTEUR - DTAPIPV - DTAP + IPV (QUADRACEL)' ||
        $substanceName eq 'SANOFI PASTEUR - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DPIPV - DP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTAPIPV - DTAP + IPV (UNKNOWN)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTP - TD + PERTUSSIS (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - 6VAX-F - DTAP+IPV+HEPB+HIB (HEXAVAC)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTIPV - DT + IPV (NO BRAND NAME)' ||
        $substanceName eq 'PASTEUR MERIEUX INST. - DTIPV - DT + IPV (FOREIGN)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - DTAP - DTAP (TRIPEDIA)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTPHIB - DTP + HIB (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - DTAP - DTAP (ACEL-IMUNE)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - TDAPIPV - TDAP + IPV (FOREIGN)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TDAPIPV - TDAP + IPV (DOMESTIC)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAPIPV - DTAP + IPV (INFANRIX TETRA)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - TDAP - TDAP (BOOSTRIX)' ||
        $substanceName eq 'SANOFI PASTEUR - TDAP - TDAP (ADACEL)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TDAP - TDAP (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'MASS. PUB HLTH BIOL LAB - TD - TD ADSORBED (TDVAX)' ||
        $substanceName eq 'SANOFI PASTEUR - TD - TD ADSORBED (TENIVAC)' ||
        $substanceName eq 'SANOFI PASTEUR - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - TD - TD ADSORBED (TD-RIX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - TD - TD ADSORBED (DITANRIX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - TD - TETANUS DIPHTHERIA (NO BRAND NAME)' ||
        $substanceName eq 'LEDERLE LABORATORIES - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'AVENTIS PASTEUR - TD - TETANUS DIPHTHERIA (NO BRAND NAME)' ||
        $substanceName eq 'CONNAUGHT LABORATORIES - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'SCLAVO - TD - TD ADSORBED (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA & TETANUS VACCINE';
    } elsif (
        $substanceName eq 'SMITHKLINE BEECHAM - DTAP - DTAP (INFANRIX)'                                                    ||
        $substanceName eq 'SANOFI PASTEUR - DTAP - DTAP (DAPTACEL)'                                                        ||
        $substanceName eq 'NORTH AMERICAN VACCINES - DTAP - DTAP (CERTIVA)'                                                ||
        $substanceName eq 'LEDERLE LABORATORIES - DTP - DTP (TRI-IMMUNOL)'                                                 ||
        $substanceName eq 'PFIZER\WYETH - DTP - DTP (NO BRAND NAME)'                                                       ||
        $substanceName eq 'MICHIGAN DEPT PUB HLTH - DTP - DTP (NO BRAND NAME)'                                             ||
        $substanceName eq 'SANOFI PASTEUR - DTP - DTP (NO BRAND NAME)'                                                     ||
        $substanceName eq 'NOVARTIS VACCINES AND DIAGNOSTICS - DPP - DIPHTHERIA TOXOID + PERTUSSIS + IPV (QUATRO VIRELON)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DPP - DIPHTHERIA TOXOID + PERTUSSIS + IPV (NO BRAND NAME)'               ||
        $substanceName eq 'MASS. PUB HLTH BIOL LAB - DTP - DTP (NO BRAND NAME)'                                            ||
        $substanceName eq 'CONNAUGHT LABORATORIES - DTP - DTP (NO BRAND NAME)'                                             ||
        $substanceName eq 'BAXTER HEALTHCARE CORP. - DTAP - DTAP (CERTIVA)'                                                ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTAP - DTAP (NO BRAND NAME)'                                             ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAP - DTAP (INFANRIX)'                                           ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTP - DTP (NO BRAND NAME)'                                               ||
        $substanceName eq 'EMERGENT BIOSOLUTIONS - DTP - DTP (NO BRAND NAME)'                                              ||
        $substanceName eq 'SANOFI PASTEUR - DTAP - DTAP (TRIPEDIA)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS & PERTUSSIS VACCINE';
    } elsif (
        $substanceName eq 'SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (PENTACEL)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTPIHI - DT+IPV+HIB+HEPB (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - 6VAX-F - DTAP+IPV+HEPB+HIB (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAPHEPBIP - DTAP + HEPB + IPV (INFANRIX PENTA)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAPHEPBIP - DTAP + HEPB + IPV (PEDIARIX)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAPIPV - DTAP + IPV (KINRIX)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTAPH - DTAP + HIB (NO BRAND NAME)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTAPIPVHIB - DTAP + IPV + HIB (UNKNOWN)' ||
        $substanceName eq 'MSP VACCINE COMPANY - DTPPVHBHPB - DTAP+IPV+HIB+HEPB (VAXELIS)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTAPHEPBIP - DTAP + HEPB + IPV (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - DTAPH - DTAP + HIB (TRIHIBIT)' ||
        $substanceName eq 'UNKNOWN MANUFACTURER - DTPPHIB - DTP + IPV + ACT-HIB (NO BRAND NAME)' ||
        $substanceName eq 'SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (NO BRAND NAME)' ||
        $substanceName eq 'BERNA BIOTECH, LTD. - DTPIPV - DTP + IPV (NO BRAND NAME)' ||
        $substanceName eq 'PFIZER\WYETH - DTPHIB - DTP + HIB (TETRAMUNE)' ||
        $substanceName eq 'SANOFI PASTEUR - DTPHIB - DTP + HIB (DTP + ACTHIB)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTAPIPVHIB - DTAP + IPV + HIB (INFANRIX QUINTA)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - 6VAX-F - DTAP+IPV+HEPB+HIB (INFANRIX HEXA)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS, WHOOPING COUGH, POLIOMYELITIS & HAEMOPHILIUS INFLUENZA TYPE B VACCINE';
    } elsif (
        $substanceName eq 'UNKNOWN MANUFACTURER - DTPHEP - DTP + HEP B (NO BRAND NAME)' ||
        $substanceName eq 'GLAXOSMITHKLINE BIOLOGICALS - DTPHEP - DTP + HEP B (TRITANRIX)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS & HEPATITIS B (RDNA) VACCINE';
    } elsif (
        $substanceName eq 'JANSSEN - COVID19 - COVID19 (COVID19 (JANSSEN))'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE JANSSEN';
    } elsif (
        $substanceName eq 'MODERNA - COVID19 - COVID19 (COVID19 (MODERNA))'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE MODERNA';
    } elsif (
        $substanceName eq 'MODERNA - COVID19-2 - COVID19 (COVID19 (MODERNA BIVALENT))'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE MODERNA - BIVALENT';
    } elsif (
        $substanceName eq 'PFIZER\BIONTECH - COVID19 - COVID19 (COVID19 (PFIZER-BIONTECH))'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE PFIZER-BIONTECH';
    } elsif (
        $substanceName eq 'PFIZER\BIONTECH - COVID19-2 - COVID19 (COVID19 (PFIZER-BIONTECH BIVALENT))'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE PFIZER-BIONTECH - BIVALENT';
    } elsif ($substanceName eq 'UNKNOWN MANUFACTURER - COVID19 - COVID19 (COVID19 (UNKNOWN))') {
        $substanceShortenedName = 'COVID-19 VACCINE UNKNOWN MANUFACTURER';
    } elsif ($substanceName eq 'NOVAVAX - COVID19 - COVID19 (COVID19 (NOVAVAX))') {
        $substanceShortenedName = 'COVID-19 VACCINE NOVAVAX';
    } else {
        die "unknown : substanceName : $substanceName";
    }
    my $substanceCategory;
    if ($substanceShortenedName =~ /COVID-19/) {
        $substanceCategory = 'COVID-19';
    } else {
        $substanceCategory = 'OTHER'
    }
    return ($substanceCategory, $substanceShortenedName);
}

sub parse_foreign_data {

	# Configuring expected files ; dying if they aren't found.
	my $dataFile     = "$cdcForeignFolder/NonDomestic" . 'VAERSDATA.csv';
	my $symptomsFile = "$cdcForeignFolder/NonDomestic" . 'VAERSSYMPTOMS.csv';
	my $vaccinesFile = "$cdcForeignFolder/NonDomestic" . 'VAERSVAX.csv';
	die "missing mandatory file in [$cdcForeignFolder]" if !-f $dataFile || !-f $symptomsFile || !-f $vaccinesFile;
	say "dataFile     : $dataFile";
	say "symptomsFile : $symptomsFile";
	say "vaccinesFile : $vaccinesFile";

	# Fetching notices - vaccines relations.
	open my $vaccinesIn, '<:', $vaccinesFile;
	my $expectedValues;
	my $vaccinesCsv = Text::CSV_XS->new ({ binary => 1 });
	my %vaccinesLabels = ();
	my %reportsVaccines = ();
	my $dRNum = 0;
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
			my $cdcReportInternalId = $values{'VAERS_ID'} // die;
			my $cdcManufacturerName = $values{'VAX_MANU'} // die;
			my $cdcVaccineTypeName = $values{'VAX_TYPE'} // die;
			my $cdcVaccineLotNumber = $values{'VAX_LOT'} // die;
			my $cdcVaccineName = $values{"VAX_NAME\n"} // die;
        	my $drugName = "$cdcManufacturerName - $cdcVaccineTypeName - $cdcVaccineName";

        	# We verify here that the vaccine is indeed related to a COVID one.
        	my ($substanceCategory, $substanceShortenedName) = substance_synthesis($drugName);
        	next unless $substanceCategory && $substanceCategory eq 'COVID-19';
        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE PFIZER-BIONTECH';
        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE MODERNA';
        	# next unless $substanceShortenedName eq 'COVID-19 VACCINE JANSSEN';
			my %o = ();
			$o{'substanceCategory'} = $substanceCategory;
			$o{'substanceShortenedName'} = $substanceShortenedName;
			$o{'lotNumber'} = $cdcVaccineLotNumber;
			$o{'cdcVaccineName'} = $cdcVaccineName;
			$o{'dose'} = $dose;
			push @{$reportsVaccines{$cdcReportInternalId}->{'vaccines'}}, \%o;
		}
	}
	close $vaccinesIn;	

	# Fetching notices - symptoms relations.
	open my $symptomsIn, '<:', $symptomsFile;
	my $symptomsCsv = Text::CSV_XS->new ({ binary => 1 });
	my %symptomsLabels = ();
	$dRNum = 0;
	my %reportsSymptoms = ();
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
			my $cdcReportInternalId  = $values{'VAERS_ID'} // die;
			my $symptom1 = $values{'SYMPTOM1'} // die;
			my $symptom2 = $values{'SYMPTOM2'};
			my $symptom3 = $values{'SYMPTOM3'};
			my $symptom4 = $values{'SYMPTOM4'};
			my $symptom5 = $values{'SYMPTOM5'};
			my @symptoms = ($symptom1, $symptom2, $symptom3, $symptom4, $symptom5);
			next unless exists $reportsVaccines{$cdcReportInternalId}->{'vaccines'};
			for my $symptomName (@symptoms) {
				next unless $symptomName && length $symptomName >= 1;
				$reportsSymptoms{$cdcReportInternalId}->{$symptomName} = 1;
			}
		}
	}
	close $symptomsIn;

	# Fetching notices.
	my $definedAge = 0;
	open my $dataIn, '<:', $dataFile;
	$dRNum = 0;
	my %dataLabels = ();
	my $dataCsv = Text::CSV_XS->new ({ binary => 1 });
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

			# Retrieving report data we care about.
			my $cdcReportInternalId = $values{'VAERS_ID'}                  // die;
			my $cdcReceptionDate    = $values{'RECVDATE'}                  // die;
			my $sCode2              = $values{'STATE'}                     // die;
			my $patientAge          = $values{'AGE_YRS'}                   // die;
			my $cdcSexInternalId    = $values{'SEX'}                       // die;
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
			$cdcVaccineAdministrator    = administrator_to_litteral($cdcVaccineAdministrator);
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
		    $vaccinationDate            = convert_date($vaccinationDate) if $vaccinationDate;
		    $deceasedDate               = convert_date($deceasedDate)    if $deceasedDate;
		    my ($receptionYear, $receptionMonth, $receptionDay) = split '-', $cdcReceptionDate;
		    my $compDate = "$receptionYear$receptionMonth$receptionDay";
		    # my $ageGroup;
		    # if (defined $patientAge) {
		    # 	$definedAge++;
		    # # 	$ageGroups = age_to_age_group($patientAge);
		    # }
		    # else {
		    # 	$ageGroups = 'Undefined Age';
		    # }
			my $immProjectNumber        = $values{'SPLTTYPE'};

			# Taking care of building stats.
			next unless exists $reportsVaccines{$cdcReportInternalId}->{'vaccines'};
		    if (defined $patientAge) {
		    	$definedAge++;
		    # 	$ageGroups = age_to_age_group($patientAge);
		    }

			my %o = ();
			$o{'cdcReportInternalId'} = $cdcReportInternalId;
			$o{'cdcReceptionDate'} = $cdcReceptionDate;
			$o{'source'}          = 'foreign';
			$o{'sCode2'}          = $sCode2;
			$o{'patientAge'}      = $patientAge;
			$o{'cdcSexInternalId'} = $cdcSexInternalId;
			$o{'cdcSexName'}      = $cdcSexName;
			$o{'vaccinationDate'} = $vaccinationDate;
			$o{'deceasedDate'}    = $deceasedDate;
			$o{'aEDescription'} = $aEDescription;
			$o{'cdcVaccineAdministrator'} = $cdcVaccineAdministrator;
			$o{'hospitalized'}    = $hospitalized;
			$o{'permanentDisability'} = $permanentDisability;
			$o{'lifeThreatning'}  = $lifeThreatning;
			$o{'patientDied'} = $patientDied;
			$o{'immProjectNumber'} = $immProjectNumber;
			for my $ausSymptomName (sort keys %{$reportsSymptoms{$cdcReportInternalId}}) {
				$o{'symptoms'}->{$ausSymptomName} = 1;
			}
			my $lastProductTaken;
			for my $vaccData (@{$reportsVaccines{$cdcReportInternalId}->{'vaccines'}}) {
				my $substanceShortenedName = %$vaccData{'substanceShortenedName'} // die;
				$lastProductTaken = $substanceShortenedName;
				push @{$o{'vaccines'}}, \%$vaccData;
			}
			die unless $lastProductTaken;
			if ($patientDied) {
				$stats{$lastProductTaken}->{'totalDeaths'}++;
			}
			$totalReports++;
			push @{$reportsByDates{$compDate}}, \%o;
		}
	}
	close $dataIn;
	say "totalReports : $totalReports";
	say "definedAge : $definedAge";
}
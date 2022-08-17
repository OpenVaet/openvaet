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

my $sourceId    = 2;                           # DB hard-coded corresponding value.
my $cdcFolder   = "raw_data/AllVAERSDataCSVS"; # Where we expect to find CDC's data folder in the project's root folder.
my $statesFile  = "tasks/cdc/states.csv";      # File containing CDC's states.

my %statesCodes = ();
parse_states();

# Verifies we have the expected folder.
unless (-d $cdcFolder) {
	say "No CDC data found on $cdcFolder. Exiting";
	exit;
}

# Parsing each year of CDC's data.
my %years = ();
parse_cdc_years();

# Fetching data which already has been indexed.
my $latestCdcStateId     = 0;
my %cdcStates            = ();
cdc_states();
my $latestCdcAgeId       = 0;
my %cdcAges              = ();
cdc_ages();
my $latestCdcSexeId      = 0;
my %cdcSexes             = ();
cdc_sexes();
my $latestCdcReportId    = 0;
my %cdcReports           = ();
cdc_reports();
my $latestCdcSymptomId   = 0;
my %cdcSymptoms          = ();
cdc_symptoms();
my $latestCdcReportSymptomId = 0;
my %cdcReportSymptoms        = ();
cdc_report_symptoms();
my $latestCdcManufacturerId  = 0;
my %cdcManufacturers  = ();
cdc_manufacturers();
my $latestCdcVaccineTypeId   = 0;
my %cdcVaccineTypes  = ();
cdc_vaccine_types();
my %cdcVaccines  = ();
my $latestCdcVaccineId = 0;
cdc_vaccines();
my $latestCdcReportVaccineId = 0;
my %cdcReportVaccines = ();
cdc_report_vaccines();

# For each year, reading reports, symptoms related, and vaccines related.
parse_yearly_data();

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
		# say "filePath : $filePath";
		# say "file     : $file";
		# say "year     : $year";
		$years{$year} = 1;
	}
}

sub cdc_states {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateId, internalId as cdcStateInternalId, name as cdcStateName FROM cdc_state WHERE id > $latestCdcStateId", 'cdcStateId');
	for my $cdcStateId (sort{$a <=> $b} keys %$tb) {
		$latestCdcStateId = $cdcStateId;
		my $cdcStateInternalId    = %$tb{$cdcStateId}->{'cdcStateInternalId'}   // die;
		my $cdcStateName  = %$tb{$cdcStateId}->{'cdcStateName'} // die;
		$cdcStates{$cdcStateInternalId}->{'cdcStateId'} = $cdcStateId;
		$cdcStates{$cdcStateInternalId}->{'cdcStateName'} = $cdcStateName;
	}
}

sub cdc_ages {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcAgeId, internalId as cdcAgeInternalId, name as cdcAgeName FROM cdc_age WHERE id > $latestCdcAgeId", 'cdcAgeId');
	for my $cdcAgeId (sort{$a <=> $b} keys %$tb) {
		$latestCdcAgeId = $cdcAgeId;
		my $cdcAgeInternalId  = %$tb{$cdcAgeId}->{'cdcAgeInternalId'} // die;
		my $cdcAgeName  = %$tb{$cdcAgeId}->{'cdcAgeName'} // die;
		$cdcAges{$cdcAgeInternalId}->{'cdcAgeId'}   = $cdcAgeId;
		$cdcAges{$cdcAgeInternalId}->{'cdcAgeName'} = $cdcAgeName;
	}
}

sub cdc_sexes {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcSexeId, internalId as cdcSexInternalId, name as cdcSexName FROM cdc_sexe WHERE id > $latestCdcSexeId", 'cdcSexeId');
	for my $cdcSexeId (sort{$a <=> $b} keys %$tb) {
		$latestCdcSexeId = $cdcSexeId;
		my $cdcSexInternalId  = %$tb{$cdcSexeId}->{'cdcSexInternalId'} // die;
		my $cdcSexName        = %$tb{$cdcSexeId}->{'cdcSexName'}       // die;
		$cdcSexes{$cdcSexInternalId}->{'cdcSexeId'} = $cdcSexeId;
		$cdcSexes{$cdcSexInternalId}->{'cdcSexName'} = $cdcSexName;
	}
}

sub cdc_reports {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportId, internalId as cdcReportInternalId FROM cdc_report WHERE id > $latestCdcReportId", 'cdcReportId');
	for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
		$latestCdcReportId      = $cdcReportId;
		my $cdcReportInternalId = %$tb{$cdcReportId}->{'cdcReportInternalId'} // die;
		$cdcReports{$cdcReportInternalId}->{'cdcReportId'} = $cdcReportId;
	}
}

sub cdc_manufacturers {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcManufacturerId, name as cdcManufacturerName FROM cdc_manufacturer WHERE id > $latestCdcManufacturerId", 'cdcManufacturerId');
	for my $cdcManufacturerId (sort{$a <=> $b} keys %$tb) {
		$latestCdcManufacturerId = $cdcManufacturerId;
		my $cdcManufacturerName  = %$tb{$cdcManufacturerId}->{'cdcManufacturerName'} // die;
		$cdcManufacturers{$cdcManufacturerName}->{'cdcManufacturerId'} = $cdcManufacturerId;
	}
}

sub cdc_vaccine_types {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcVaccineTypeId, name as cdcVaccineTypeName FROM cdc_vaccine_type WHERE id > $latestCdcVaccineTypeId", 'cdcVaccineTypeId');
	for my $cdcVaccineTypeId (sort{$a <=> $b} keys %$tb) {
		$latestCdcVaccineTypeId = $cdcVaccineTypeId;
		my $cdcVaccineTypeName  = %$tb{$cdcVaccineTypeId}->{'cdcVaccineTypeName'} // die;
		$cdcVaccineTypes{$cdcVaccineTypeName}->{'cdcVaccineTypeId'} = $cdcVaccineTypeId;
	}
}

sub cdc_report_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportSymptomId, cdcReportId, cdcSymptomId FROM cdc_report_symptom WHERE id > $latestCdcReportSymptomId", 'cdcReportSymptomId');
	for my $cdcReportSymptomId (sort{$a <=> $b} keys %$tb) {
		$latestCdcReportSymptomId = $cdcReportSymptomId;
		my $cdcReportId = %$tb{$cdcReportSymptomId}->{'cdcReportId'} // die;
		my $cdcSymptomId = %$tb{$cdcReportSymptomId}->{'cdcSymptomId'} // die;
		$cdcReportSymptoms{$cdcReportId}->{$cdcSymptomId}->{'cdcReportSymptomId'} = $cdcReportSymptomId;
	}
}

sub cdc_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom WHERE id > $latestCdcSymptomId", 'cdcSymptomId');
	for my $cdcSymptomId (sort{$a <=> $b} keys %$tb) {
		$latestCdcSymptomId = $cdcSymptomId;
		my $cdcSymptomName = %$tb{$cdcSymptomId}->{'cdcSymptomName'} // die;
		$cdcSymptoms{$cdcSymptomName}->{'cdcSymptomId'} = $cdcSymptomId;
	}
}

sub cdc_vaccines {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcVaccineId, cdcManufacturerId, cdcVaccineTypeId, name as cdcVaccineName FROM cdc_vaccine WHERE id > $latestCdcVaccineId", 'cdcVaccineId');
	for my $cdcVaccineId (sort{$a <=> $b} keys %$tb) {
		$latestCdcVaccineId   = $cdcVaccineId;
		my $cdcManufacturerId = %$tb{$cdcVaccineId}->{'cdcManufacturerId'} // die;
		my $cdcVaccineTypeId  = %$tb{$cdcVaccineId}->{'cdcVaccineTypeId'}  // die;
		my $cdcVaccineName    = %$tb{$cdcVaccineId}->{'cdcVaccineName'}    // die;
		$cdcVaccines{$cdcManufacturerId}->{$cdcVaccineTypeId}->{$cdcVaccineName}->{'cdcVaccineId'} = $cdcVaccineId;
	}
}

sub cdc_report_vaccines {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportVaccineId, cdcReportId, cdcVaccineId FROM cdc_report_vaccine WHERE id > $latestCdcReportVaccineId", 'cdcReportVaccineId');
	for my $cdcReportVaccineId (sort{$a <=> $b} keys %$tb) {
		$latestCdcReportVaccineId = $cdcReportVaccineId;
		my $cdcReportId  = %$tb{$cdcReportVaccineId}->{'cdcReportId'}  // die;
		my $cdcVaccineId = %$tb{$cdcReportVaccineId}->{'cdcVaccineId'} // die;
		$cdcReportVaccines{$cdcReportId}->{$cdcVaccineId} = $cdcReportVaccineId;
	}
}

sub parse_yearly_data {
	for my $year (sort{$a <=> $b} keys %years) {

		# Configuring expected files ; dying if they aren't found.
		my $dataFile     = "$cdcFolder/$year" . 'VAERSDATA.csv';
		my $symptomsFile = "$cdcFolder/$year" . 'VAERSSYMPTOMS.csv';
		my $vaccinesFile = "$cdcFolder/$year" . 'VAERSVAX.csv';
		die "missing mandatory file for year [$year] in [$cdcFolder]" if !-f $dataFile || !-f $symptomsFile || !-f $vaccinesFile;
		say "dataFile     : $dataFile";
		say "symptomsFile : $symptomsFile";
		say "vaccinesFile : $vaccinesFile";
		say "year         : $year";

		# Fetching notices.
		open my $dataIn, '<:', $dataFile;
		my $utf8DataFile = "$cdcFolder/$year" . 'VAERSDATA_utf8.csv';
		my $dRNum = 0;
		my %dataLabels = ();
		my $expectedValues = ();
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
				my $cdcReportInternalId = $values{'VAERS_ID'}                   // die;
				my $cdcReceptionDate    = $values{'RECVDATE'}                   // die;
				my $sCode2              = $values{'STATE'}                      // die;
				my $stateName           = $statesCodes{$sCode2}->{'stateName'}  // "Unknown";
				my $stateInternalId     = $statesCodes{$sCode2}->{'internalId'} // "00";
				unless (exists $cdcStates{$stateInternalId}->{'cdcStateId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_state (internalId, name) VALUES (?, ?)");
					$sth->execute($stateInternalId, $stateName) or die $sth->err();
					cdc_states();
				}
				my $cdcStateId       = $cdcStates{$stateInternalId}->{'cdcStateId'} // die;
				my $patientAge       = $values{'AGE_YRS'}                    // die;
				my ($cdcAgeInternalId,
					$cdcAgeName)     = age_to_age_group($patientAge);
				unless (exists $cdcAges{$cdcAgeInternalId}->{'cdcAgeId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_age (internalId, name) VALUES (?, ?)");
					$sth->execute($cdcAgeInternalId, $cdcAgeName) or die $sth->err();
					cdc_ages();
				}
				my $cdcAgeId         = $cdcAges{$cdcAgeInternalId}->{'cdcAgeId'} // die;
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
				unless (exists $cdcSexes{$cdcSexInternalId}->{'cdcSexeId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_sexe (internalId, name) VALUES (?, ?)");
					$sth->execute($cdcSexInternalId, $cdcSexName) or die $sth->err();
					cdc_sexes();
				}
				my $cdcSexeId = $cdcSexes{$cdcSexInternalId}->{'cdcSexeId'} // die;
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
			    $vaccinationDate            = convert_date($vaccinationDate) if $vaccinationDate;
			    $deceasedDate               = convert_date($deceasedDate)    if $deceasedDate;
				# say "cdcReceptionDate        : $cdcReceptionDate";
				# say "stateName               : $stateName";
				# say "stateInternalId         : $stateInternalId";
				# say "cdcStateId              : $cdcStateId";
				# say "cdcAgeName              : $cdcAgeName";
				# say "patientAge              : $patientAge";
				# say "cdcAgeId                : $cdcAgeId";
				# say "cdcVaccineAdministrator : $cdcVaccineAdministrator";
				# say "aEDescription           : $aEDescription";
				# say "hospitalized            : $hospitalized";
				# say "permanentDisability     : $permanentDisability";
				# say "lifeThreatning          : $lifeThreatning";
				# say "patientDied             : $patientDied";
				unless (exists $cdcReports{$cdcReportInternalId}->{'cdcReportId'}) {
					my $sth = $dbh->prepare("
						INSERT INTO cdc_report (
							cdcStateId, internalId, vaccinationDate, cdcReceptionDate, cdcSexeId,
							cdcVaccineAdministrator, patientAge, aEDescription, cdcAgeId, patientDied,
							lifeThreatning, hospitalized, permanentDisability
						) VALUES (
							?, ?, ?, ?, ?,
							?, ?, ?, ?, $patientDied,
							$lifeThreatning, $hospitalized, $permanentDisability
						)");
					$sth->execute(
						$cdcStateId, $cdcReportInternalId, $vaccinationDate, $cdcReceptionDate, $cdcSexeId,
						$cdcVaccineAdministrator, $patientAge, $aEDescription, $cdcAgeId
					) or die $sth->err();
					cdc_reports();
				}
				#  else {
				# 	my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
				# 	my $sth = $dbh->prepare("UPDATE cdc_report SET vaccinationDate = ?, cdcReceptionDate = ? WHERE id = $cdcReportId");
				# 	$sth->execute($vaccinationDate, $cdcReceptionDate) or die $sth->err();
				# }
				my $cdcReportId = $cdcReports{$cdcReportInternalId}->{'cdcReportId'} // die;
				# say "cdcReportId             : $cdcReportId";
				# p%values;
				# die;
				# if ($hospitalized eq 'Yes') {
				# 	$hospitalized = 1;
				# } elsif ($hospitalized eq 'No') {
				# 	$hospitalized = 0;
				# } else {
				# 	die;
				# }
				# if ($patientDied eq 'Yes') {
				# 	$patientDied = 1;
				# } elsif ($patientDied eq 'No') {
				# 	$patientDied = 0;
				# } else {
				# 	die;
				# }
				# if ($lifeThreatning eq 'Yes') {
				# 	$lifeThreatning = 1;
				# } elsif ($lifeThreatning eq 'No') {
				# 	$lifeThreatning = 0;
				# } else {
				# 	die;
				# }
				# if ($permanentDisability eq 'Yes') {
				# 	$permanentDisability = 1;
				# } elsif ($permanentDisability eq 'No') {
				# 	$permanentDisability = 0;
				# } else {
				# 	die;
				# }
				# my $cdcSeriousness = %$reportData{'Event Information'}->{'Serious'}           // die;
				# if ($cdcSeriousness eq 'Yes') {
				# 	$cdcSeriousness = 1;
				# } elsif ($cdcSeriousness eq 'No') {
				# 	$cdcSeriousness = 2;
				# } else {
				# 	die "cdcSeriousness : $cdcSeriousness";
				# }
			}
		}
		close $dataIn;

		# Fetching notices - vaccines relations.
		open my $symptomsIn, '<:', $symptomsFile;
		my $symptomsCsv = Text::CSV_XS->new ({ binary => 1 });
		my %symptomsLabels = ();
		$dRNum = 0;
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
				my $vaersId  = $values{'VAERS_ID'} // die;
				my $symptom1 = $values{'SYMPTOM1'} // die;
				my $symptom2 = $values{'SYMPTOM2'};
				my $symptom3 = $values{'SYMPTOM3'};
				my $symptom4 = $values{'SYMPTOM4'};
				my $symptom5 = $values{'SYMPTOM5'};
				my @symptoms = ($symptom1, $symptom2, $symptom3, $symptom4, $symptom5);
				my $cdcReportId = $cdcReports{$vaersId}->{'cdcReportId'} // die;
				for my $symptomName (@symptoms) {
					next unless $symptomName && length $symptomName >= 1;
					unless (exists $cdcSymptoms{$symptomName}->{'cdcSymptomId'}) {
						my $sth = $dbh->prepare("INSERT INTO cdc_symptom (name) VALUES (?)");
						$sth->execute($symptomName) or die $sth->err();
						cdc_symptoms();
					}
					my $cdcSymptomId = $cdcSymptoms{$symptomName}->{'cdcSymptomId'} // die;
					unless (exists $cdcReportSymptoms{$cdcReportId}->{$cdcSymptomId}->{'cdcReportSymptomId'}) {
						my $sth = $dbh->prepare("INSERT INTO cdc_report_symptom (cdcReportId, cdcSymptomId) VALUES (?, ?)");
						$sth->execute($cdcReportId, $cdcSymptomId) or die $sth->err();
						cdc_report_symptoms();
					}
				}
			}
		}
		close $symptomsIn;

		# Fetching notices - reactions relations.
		open my $vaccinesIn, '<:', $vaccinesFile;
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
				my $cdcReportId = $cdcReports{$vaersId}->{'cdcReportId'} // die;
				my $cdcManufacturerName = $values{'VAX_MANU'} // die;
				unless (exists $cdcManufacturers{$cdcManufacturerName}->{'cdcManufacturerId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_manufacturer (name) VALUES (?)");
					$sth->execute($cdcManufacturerName) or die $sth->err();
					cdc_manufacturers();
				}
				my $cdcManufacturerId  = $cdcManufacturers{$cdcManufacturerName}->{'cdcManufacturerId'} // die;
				my $cdcVaccineTypeName = $values{'VAX_TYPE'} // die;
				unless (exists $cdcVaccineTypes{$cdcVaccineTypeName}->{'cdcVaccineTypeId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_vaccine_type (name) VALUES (?)");
					$sth->execute($cdcVaccineTypeName) or die $sth->err();
					cdc_vaccine_types();
				}
				my $cdcVaccineTypeId = $cdcVaccineTypes{$cdcVaccineTypeName}->{'cdcVaccineTypeId'} // die;
				my $cdcVaccineName = $values{"VAX_NAME\n"} // die;
				unless (exists $cdcVaccines{$cdcManufacturerId}->{$cdcVaccineTypeId}->{$cdcVaccineName}->{'cdcVaccineId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_vaccine (cdcManufacturerId, cdcVaccineTypeId, name) VALUES (?, ?, ?)");
					$sth->execute($cdcManufacturerId, $cdcVaccineTypeId, $cdcVaccineName) or die $sth->err();
					cdc_vaccines();
				}
				my $cdcVaccineId = $cdcVaccines{$cdcManufacturerId}->{$cdcVaccineTypeId}->{$cdcVaccineName}->{'cdcVaccineId'} // die;
				# say "cdcReportId        : $cdcReportId";
				# say "cdcVaccineTypeId   : $cdcVaccineTypeId";
				# say "cdcManufacturerId  : $cdcManufacturerId";
				# say "vaersId            : $vaersId";
				# say "cdcVaccineTypeName : $cdcVaccineTypeName";
				# say "cdcVaccineName     : $cdcVaccineName";
				# say "cdcVaccineId       : $cdcVaccineId";
				unless (exists $cdcReportVaccines{$cdcReportId}->{$cdcVaccineId}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_report_vaccine (cdcReportId, cdcVaccineId, dose) VALUES (?, ?, ?)");
					$sth->execute($cdcReportId, $cdcVaccineId, $dose) or die $sth->err();
					cdc_report_vaccines();
				}
				# p%values;
				# die;
				# my $vaersId  = $values{'VAERS_ID'} // die;
				# my $symptom1 = $values{'SYMPTOM1'} // die;
				# my $symptom2 = $values{'SYMPTOM2'};
				# if (!$symptom2) {
				# 	p%values;
				# 	die;
				# }
			}
		}
		close $vaccinesIn;
	}
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
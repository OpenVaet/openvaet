#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use JSON;
use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(usleep);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use global;
use config;
use time;

# Profile Path Configuration.
my $sourceId          = 2; # DB hard-coded corresponding value.

# Fetching indexed reports.
my %cdcReports        = ();
my %cdcManufacturers  = ();
my $latestCdcManufacturerId = 0;
cdc_manufacturers();
my %cdcVaccineTypes  = ();
my $latestCdcVaccineTypeId = 0;
cdc_vaccine_types();
my %cdcVaccines  = ();
my $latestCdcVaccineId = 0;
cdc_vaccines();
my %cdcStates = ();
cdc_states();
my %cdcSexes = ();
for my $cdcSex (sort keys %{$enums{'cdcSex'}}) {
	my $cdcSexName = $enums{'cdcSex'}->{$cdcSex} // die;
	$cdcSexes{$cdcSexName}->{'cdcSex'} = $cdcSex;
}
my $latestCdcSymptomId = 0;
my %cdcSymptoms = ();
cdc_symptoms();
my $latestCdcReportSymptomId = 0;
my %cdcReportSymptoms = ();
cdc_report_symptoms();
my $latestCdcReportVaccineId = 0;
my %cdcReportVaccines = ();
cdc_report_vaccines();
cdc_reports();

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

sub cdc_states {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateId, name as cdcStateName FROM cdc_state", 'cdcStateId');
	for my $cdcStateId (sort{$a <=> $b} keys %$tb) {
		my $cdcStateName = %$tb{$cdcStateId}->{'cdcStateName'} // die;
		$cdcStates{$cdcStateName}->{'cdcStateId'} = $cdcStateId;
	}
}

sub cdc_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcSymptomId, name as cdcSymptomName FROM cdc_symptom WHERE id > $latestCdcSymptomId", 'cdcSymptomId');
	for my $cdcSymptomId (sort{$a <=> $b} keys %$tb) {
		$latestCdcSymptomId = $cdcSymptomId;
		my $cdcSymptomName  = %$tb{$cdcSymptomId}->{'cdcSymptomName'} // die;
		$cdcSymptoms{$cdcSymptomName}->{'cdcSymptomId'} = $cdcSymptomId;
	}
}

sub cdc_report_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcReportSymptomId, cdcReportId, cdcSymptomId FROM cdc_report_symptom WHERE id > $latestCdcReportSymptomId", 'cdcReportSymptomId');
	for my $cdcReportSymptomId (sort{$a <=> $b} keys %$tb) {
		$latestCdcReportSymptomId = $cdcReportSymptomId;
		my $cdcReportId  = %$tb{$cdcReportSymptomId}->{'cdcReportId'}  // die;
		my $cdcSymptomId = %$tb{$cdcReportSymptomId}->{'cdcSymptomId'} // die;
		$cdcReportSymptoms{$cdcReportId}->{$cdcSymptomId} = $cdcReportSymptomId;
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

sub cdc_reports {
	my $current = 0;
	my $tb      = $dbh->selectall_hashref("SELECT id as cdcReportId, internalId, reportData FROM cdc_report WHERE detailsTimestamp IS NOT NULL AND parsingTimestamp IS NULL", 'cdcReportId');
	my $total   = keys %$tb;
	for my $cdcReportId (sort{$a <=> $b} keys %$tb) {
		my $reportData = %$tb{$cdcReportId}->{'reportData'};
		$reportData = decode_json($reportData);
		my $currentDatetime = time::current_datetime();
		$current++;
		STDOUT->printflush("\r$currentDatetime - Parsing [Reports' Details] - [$current / $total]                          ");

		# For each vaccine involved in the report ...
		for my $vaccineNum (sort{$a <=> $b} keys %{%$reportData{'Vaccines Details'}}) {

			# Extracting vaccine manufacturer.
			my $cdcManufacturerName = %$reportData{'Vaccines Details'}->{$vaccineNum}->{'Manufacturer'} // die;
			unless (exists $cdcManufacturers{$cdcManufacturerName}->{'cdcManufacturerId'}) {
				my $sth = $dbh->prepare("INSERT INTO cdc_manufacturer (name) VALUES (?)");
				$sth->execute($cdcManufacturerName) or die $sth->err();
				cdc_manufacturers();
			}
			my $cdcManufacturerId = $cdcManufacturers{$cdcManufacturerName}->{'cdcManufacturerId'} // die;
			
			# Extracting vaccine type.
			my $cdcVaccineTypeName = %$reportData{'Vaccines Details'}->{$vaccineNum}->{'Vaccine Type'} // die;
			unless (exists $cdcVaccineTypes{$cdcVaccineTypeName}->{'cdcVaccineTypeId'}) {
				my $sth = $dbh->prepare("INSERT INTO cdc_vaccine_type (name) VALUES (?)");
				$sth->execute($cdcVaccineTypeName) or die $sth->err();
				cdc_vaccine_types();
			}
			my $cdcVaccineTypeId = $cdcVaccineTypes{$cdcVaccineTypeName}->{'cdcVaccineTypeId'} // die;

			# Extracting vaccine.
			my $cdcVaccineName = %$reportData{'Vaccines Details'}->{$vaccineNum}->{'Vaccine'} // die;
			unless (exists $cdcVaccines{$cdcManufacturerId}->{$cdcVaccineTypeId}->{$cdcVaccineName}->{'cdcVaccineId'}) {
				my $sth = $dbh->prepare("INSERT INTO cdc_vaccine (cdcManufacturerId, cdcVaccineTypeId, name) VALUES (?, ?, ?)");
				$sth->execute($cdcManufacturerId, $cdcVaccineTypeId, $cdcVaccineName) or die $sth->err();
				cdc_vaccines();
			}
			my $cdcVaccineId = $cdcVaccines{$cdcManufacturerId}->{$cdcVaccineTypeId}->{$cdcVaccineName}->{'cdcVaccineId'} // die;

			# Extracting dose.
			my $dose = %$reportData{'Vaccines Details'}->{$vaccineNum}->{'Dose'} // die;
			# say "cdcManufacturerId       : $cdcManufacturerId";
			# say "cdcManufacturerName     : $cdcManufacturerName";
			# say "cdcVaccineTypeId        : $cdcVaccineTypeId";
			# say "cdcVaccineTypeName      : $cdcVaccineTypeName";
			# say "cdcVaccineName          : $cdcVaccineName";
			# say "cdcVaccineId            : $cdcVaccineId";
			# say "dose                    : $dose";
			unless (exists $cdcReportVaccines{$cdcReportId}->{$cdcVaccineId}) {
				my $sth = $dbh->prepare("INSERT INTO cdc_report_vaccine (cdcReportId, cdcVaccineId, dose) VALUES (?, ?, ?)");
				$sth->execute($cdcReportId, $cdcVaccineId, $dose) or die $sth->err();
				cdc_report_vaccines();
			}
		}

		# Extracting data we want (patient sex, age, seriousness, state, date vaccinated, date report received, date died, AE description, vaccine administrator).
		my $cdcSexName     = %$reportData{'Event Information'}->{'Sex'}               // die;
		my $cdcSex         = $cdcSexes{$cdcSexName}->{'cdcSex'}                       // die;
		my $patientAge     = %$reportData{'Event Information'}->{'Patient Age'}       // die;
		$patientAge        = undef unless $patientAge;
		my $cdcSeriousness = %$reportData{'Event Information'}->{'Serious'}           // die;
		if ($cdcSeriousness eq 'Yes') {
			$cdcSeriousness = 1;
		} elsif ($cdcSeriousness eq 'No') {
			$cdcSeriousness = 2;
		} else {
			die "cdcSeriousness : $cdcSeriousness";
		}
		my $cdcStateName            = %$reportData{'Event Information'}->{'State / Territory'}     // die;
		my $cdcStateId              = $cdcStates{$cdcStateName}->{'cdcStateId'}                    // die;
		my $vaccinationDate         = %$reportData{'Event Information'}->{'Date Vaccinated'}      // die;
		my $cdcReceptionDate        = %$reportData{'Event Information'}->{'Date Report Received'} // die;
		my $deceasedDate            = %$reportData{'Event Information'}->{'Date Died'};
		my $aEDescription           = %$reportData{'Event Information'}->{'Adverse Event Description'};
		my $cdcVaccineAdministrator = %$reportData{'Event Information'}->{'Vaccine Administered By'};
		$cdcVaccineAdministrator    = administrator_to_enum($cdcVaccineAdministrator);

		if (%$reportData{'Symptom'}) {

			# Extracting symptoms.
			for my $cdcSymptomName (@{%$reportData{'Symptom'}}) {
				# say "cdcSymptomName          : $cdcSymptomName";
				unless (exists $cdcSymptoms{$cdcSymptomName}->{'cdcSymptomId'}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_symptom (name) VALUES (?)");
					$sth->execute($cdcSymptomName) or die $sth->err();
					cdc_symptoms();
				}
				my $cdcSymptomId = $cdcSymptoms{$cdcSymptomName}->{'cdcSymptomId'} // die;
				unless (exists $cdcReportSymptoms{$cdcReportId}->{$cdcSymptomId}) {
					my $sth = $dbh->prepare("INSERT INTO cdc_report_symptom (cdcReportId, cdcSymptomId) VALUES (?, ?)");
					$sth->execute($cdcReportId, $cdcSymptomId) or die $sth->err();
					cdc_report_symptoms();
				}
				# say "cdcSymptomId            : $cdcSymptomId";
			}
		}

		# Extracting tags (hospitalized, life threatning, death, permanent disability)
		my $hospitalized        = %$reportData{'Event Categories'}->{'Hospitalized'}          // die;
		my $permanentDisability = %$reportData{'Event Categories'}->{'Permanent Disability'}  // die;
		my $lifeThreatning      = %$reportData{'Event Categories'}->{'Life Threatening'}      // die;
		my $patientDied         = %$reportData{'Event Categories'}->{'Death'}                 // die;
		if ($hospitalized eq 'Yes') {
			$hospitalized = 1;
		} elsif ($hospitalized eq 'No') {
			$hospitalized = 0;
		} else {
			die;
		}
		if ($patientDied eq 'Yes') {
			$patientDied = 1;
		} elsif ($patientDied eq 'No') {
			$patientDied = 0;
		} else {
			die;
		}
		if ($lifeThreatning eq 'Yes') {
			$lifeThreatning = 1;
		} elsif ($lifeThreatning eq 'No') {
			$lifeThreatning = 0;
		} else {
			die;
		}
		if ($permanentDisability eq 'Yes') {
			$permanentDisability = 1;
		} elsif ($permanentDisability eq 'No') {
			$permanentDisability = 0;
		} else {
			die;
		}
		# say "*" x 50;
		# say "cdcSexName              : $cdcSexName";
		# say "cdcReportId             : $cdcReportId";
		# say "cdcSex                  : $cdcSex";
		# say "patientAge              : [$patientAge]";
		# say "cdcSeriousness          : $cdcSeriousness";
		# say "cdcStateName            : $cdcStateName";
		# say "cdcStateId              : $cdcStateId";
		# say "vaccinationDate         : $vaccinationDate";
		# say "cdcReceptionDate        : $cdcReceptionDate";
		# say "deceasedDate            : $deceasedDate" if $deceasedDate;
		# say "aEDescription           : $aEDescription";
		# say "cdcVaccineAdministrator : $cdcVaccineAdministrator";
		# say "patientDied             : $patientDied";
		# say "lifeThreatning          : $lifeThreatning";
		# say "hospitalized            : $hospitalized";
		# say "permanentDisability     : $permanentDisability";
		# p$reportData;
		# die;
		my $sth = $dbh->prepare("
			UPDATE cdc_report SET
				vaccinationDate         = ?,
				cdcReceptionDate        = ?,
				cdcSex                  = ?,
				cdcSeriousness          = ?,
				cdcVaccineAdministrator = ?,
				patientAge              = ?,
				aEDescription           = ?,
				patientDied             = $patientDied,
				lifeThreatning          = $lifeThreatning,
				hospitalized            = $hospitalized,
				permanentDisability = $permanentDisability,
				parsingTimestamp = UNIX_TIMESTAMP()
			WHERE id = $cdcReportId");
		$sth->execute(
			$vaccinationDate,
			$cdcReceptionDate,
			$cdcSex,
			$cdcSeriousness,
			$cdcVaccineAdministrator,
			$patientAge,
			$aEDescription
		) or die $sth->err();
	}
	say "" if $total;
}

sub administrator_to_enum {
	my ($cdcVaccineAdministrator) = @_;
	if ($cdcVaccineAdministrator eq 'Military') {
		$cdcVaccineAdministrator = 1;
	} elsif ($cdcVaccineAdministrator eq 'Other') {
		$cdcVaccineAdministrator = 2;
	} elsif ($cdcVaccineAdministrator eq 'Private') {
		$cdcVaccineAdministrator = 3;
	} elsif ($cdcVaccineAdministrator eq 'Public') {
		$cdcVaccineAdministrator = 4;
	} elsif ($cdcVaccineAdministrator eq 'Unknown') {
		$cdcVaccineAdministrator = 5;
	} elsif ($cdcVaccineAdministrator eq 'Pharmacy *') {
		$cdcVaccineAdministrator = 6;
	} elsif ($cdcVaccineAdministrator eq 'Work *') {
		$cdcVaccineAdministrator = 7;
	} elsif ($cdcVaccineAdministrator eq 'School *') {
		$cdcVaccineAdministrator = 8;
	} elsif ($cdcVaccineAdministrator eq 'Senior Living *') {
		$cdcVaccineAdministrator = 9;
	} else {
		die "cdcVaccineAdministrator : $cdcVaccineAdministrator";
	}
	return $cdcVaccineAdministrator;
}
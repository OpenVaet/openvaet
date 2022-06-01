#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path rmtree);
use Text::CSV qw( csv );
use Math::Round qw(nearest);
use List::Util qw< min max >;
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

my $vaersFolder                    = "raw_data/AllVAERSDataCSVS";          # Where we expect to find VAERS's data folder in the project's root folder.
my $statesFile                     = "tasks/cdc/states.csv";               # File containing VAERS's states.
my $fromYear                       = 2020;                                 # We start integrating data from this year (reportingYear >= fromYear).
my $reportsFolder1                 = 'stats/requalifiedAsPregnancies';     # Various sub-folders which will contain the current JSON extracts when the analysis is ready.
my $reportsFolder2                 = 'stats/requalifiedAsNonPregnancies';
my $reportsFolder3                 = 'stats/improperlyTaggedAsPregnancy';
my $reportsFolder4                 = 'stats/motherDiedInPregnancy';
my $reportsFolder5                 = 'stats/motherSeriousAEInPregnancy';
my $reportsFolder6                 = 'stats/childDiedButIsntFlagged';
my $reportsFolder7                 = 'stats/childDied';
my $reportsFolder8                 = 'stats/falsePositiveChildrenDeaths';
my %reportsExports                 = ();                                   # Stores the references of the exported reports.

my $latestSymptomId                = 0;                                    # Stores the various interpretations of the symptoms we will use
my %allSymptoms                    = ();                                   # All the symptoms as we known them from the VAERS parsing
my %excludedSymptoms               = ();                                   # Symptoms which have been flagged as cause for exclusion
my %likelyPregnanciesSymptoms      = ();                                   # Symptoms indicating that the patient is probably a pregnant woman
my %severePregnanciesSymptoms      = ();                                   # Symptoms indicating a severe pregnancy complication
my %miscarriagePregnanciesSymptoms = ();                                   # Symptoms indicating a miscarriage
my %cdcStates                      = ();                                   # Stores the states as we known them from our task/cdc/parse_cdc_archive.pl parsing.
my %statesCodes                    = ();                                   # CSV file (which should be updated if a new USA state appears) storing the matching between the state code2 & its full name.

# Deleting & setting stats storage.
delete_and_set_storage();

# Verifies we have the expected data folder.
unless (-d $vaersFolder) {
	say "No VAERS data found in [$vaersFolder]. Exiting";
	exit;
}
unless (-f $statesFile) {
	say "Missing state dictionary [$statesFile]. Exiting";
	exit;
}

# Gets the CDC state from the DB. We expect all of them to be known ; therefore that the full VAERS data has already been parsed with task/cdc/parse_cdc_archive.pl
cdc_states();
parse_states();            # This will load the matchings between Code2 & State names.

vaers_fertility_symptom(); # Fetching VAERS known symptoms & their defined characteristics.

my $latestReportId                 = 0;
my %reports                        = ();
vaers_fertility_report();  # This will need to be improved before to be put to production to ensure that every data is checked for potential CDC update.


# Parsing each year of VAERS's data.
my %years = ();
parse_vaers_years();
# p%statesCodes;
# p%years;
# my %unknownSubstances = (); # DEBUG.
my %vaersStatistics  = ();
my %pregnantMothersAges = ();
my %childDeathsByStates = ();
my $cpt = 0;
parse_yearly_data();

generate_end_user_stats();
p%vaersStatistics;
# p%unknownSubstances;

sub delete_and_set_storage {
	if (-d $reportsFolder1) {
		rmtree($reportsFolder1) or die "couldn't rmtree $reportsFolder1: $!";
	}
	make_path($reportsFolder1) or die "couldn't create $reportsFolder1: $!";
	if (-d $reportsFolder2) {
		rmtree($reportsFolder2) or die "couldn't rmtree $reportsFolder2: $!";
	}
	make_path($reportsFolder2) or die "couldn't create $reportsFolder2: $!";
	if (-d $reportsFolder3) {
		rmtree($reportsFolder3) or die "couldn't rmtree $reportsFolder3: $!";
	}
	make_path($reportsFolder3) or die "couldn't create $reportsFolder3: $!";
	if (-d $reportsFolder4) {
		rmtree($reportsFolder4) or die "couldn't rmtree $reportsFolder4: $!";
	}
	make_path($reportsFolder4) or die "couldn't create $reportsFolder4: $!";
	if (-d $reportsFolder5) {
		rmtree($reportsFolder5) or die "couldn't rmtree $reportsFolder5: $!";
	}
	make_path($reportsFolder5) or die "couldn't create $reportsFolder5: $!";
	if (-d $reportsFolder6) {
		rmtree($reportsFolder6) or die "couldn't rmtree $reportsFolder6: $!";
	}
	make_path($reportsFolder6) or die "couldn't create $reportsFolder6: $!";
	if (-d $reportsFolder7) {
		rmtree($reportsFolder7) or die "couldn't rmtree $reportsFolder7: $!";
	}
	make_path($reportsFolder7) or die "couldn't create $reportsFolder7: $!";
	if (-d $reportsFolder8) {
		rmtree($reportsFolder8) or die "couldn't rmtree $reportsFolder8: $!";
	}
	make_path($reportsFolder8) or die "couldn't create $reportsFolder8: $!";
}

sub cdc_states {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateId, name as stateName FROM cdc_state", 'cdcStateId');
	for my $cdcStateId (sort{$a <=> $b} keys %$tb) {
		my $stateName = %$tb{$cdcStateId}->{'stateName'} // die;
		$cdcStates{$stateName}->{'cdcStateId'} = $cdcStateId;
	}
}

sub vaers_fertility_symptom {
	my $tb = $dbh->selectall_hashref("
		SELECT
			id as symptomId,
			name as symptomName,
			discarded,
			pregnancyRelated,
			severePregnancyRelated,
			menstrualDisorderRelated,
			foetalDeathRelated
		FROM vaers_fertility_symptom
		WHERE id > $latestSymptomId", 'symptomId');
	for my $symptomId (sort{$a <=> $b} keys %$tb) {
		$latestSymptomId = $symptomId;
		my $symptomName  = %$tb{$symptomId}->{'symptomName'} // die;
		my $discarded    = %$tb{$symptomId}->{'discarded'}   // die;
    	$discarded       = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
		my $pregnancyRelated    = %$tb{$symptomId}->{'pregnancyRelated'}   // die;
    	$pregnancyRelated       = unpack("N", pack("B32", substr("0" x 32 . $pregnancyRelated, -32)));
		my $severePregnancyRelated    = %$tb{$symptomId}->{'severePregnancyRelated'}   // die;
    	$severePregnancyRelated       = unpack("N", pack("B32", substr("0" x 32 . $severePregnancyRelated, -32)));
		my $menstrualDisorderRelated    = %$tb{$symptomId}->{'menstrualDisorderRelated'}   // die;
    	$menstrualDisorderRelated       = unpack("N", pack("B32", substr("0" x 32 . $menstrualDisorderRelated, -32)));
		my $foetalDeathRelated    = %$tb{$symptomId}->{'foetalDeathRelated'}   // die;
    	$foetalDeathRelated       = unpack("N", pack("B32", substr("0" x 32 . $foetalDeathRelated, -32)));
		$allSymptoms{$symptomName}->{'symptomId'} = $symptomId;
    	if ($discarded) {
			$excludedSymptoms{$symptomName}->{'symptomId'} = $symptomId;
    	}
    	if ($pregnancyRelated) {
			$likelyPregnanciesSymptoms{$symptomName}->{'symptomId'} = $symptomId;
    	}
    	if ($severePregnancyRelated) {
			$severePregnanciesSymptoms{$symptomName}->{'symptomId'} = $symptomId;
    	}
    	if ($foetalDeathRelated) {
			$miscarriagePregnanciesSymptoms{$symptomName}->{'symptomId'} = $symptomId;
    	}
	}
}

sub vaers_fertility_report {
	open my $out, '>:utf8', 'public/doc/vaers_fertility/arbitration_data.csv';
	say $out "VAERS_ID;PREGNANT;SERIOUS;DIED;HOSPI;LIFETHREAT;DISABL;CHILD_DEATH;VAX_DATE;ONSET_DATE;HOURS_VAX_TO_ONSET;";
	my $tb = $dbh->selectall_hashref("
		SELECT
			id as reportId,
			vaersId,
			menstrualCycleDisordersConfirmation,
			babyExposureConfirmation,
			pregnancyConfirmation,
			pregnancyConfirmationRequired,
			seriousnessConfirmationRequired,
			pregnancyDetailsConfirmationRequired,
			seriousnessConfirmation,
			patientDiedFixed,
			patientDiedFixed,
			motherAgeFixed,
			childAgeWeekFixed,
			lifeThreatningFixed,
			permanentDisabilityFixed,
			hospitalizedFixed,
			childDied,
			childSeriousAE,
			hoursBetweenVaccineAndAE,
			onsetDateFixed,
			vaccinationDateFixed
		FROM vaers_fertility_report
		WHERE id > $latestReportId", 'reportId');
	for my $reportId (sort{$a <=> $b} keys %$tb) {
		$latestReportId                          = $reportId;
		my $vaersId                              = %$tb{$reportId}->{'vaersId'}                             // die;
		my $menstrualCycleDisordersConfirmation  = %$tb{$reportId}->{'menstrualCycleDisordersConfirmation'};
		my $babyExposureConfirmation             = %$tb{$reportId}->{'babyExposureConfirmation'};
		my $pregnancyConfirmation                = %$tb{$reportId}->{'pregnancyConfirmation'};
		my $seriousnessConfirmation              = %$tb{$reportId}->{'seriousnessConfirmation'};
		my $onsetDateFixed                       = %$tb{$reportId}->{'onsetDateFixed'}       // '';
		my $vaccinationDateFixed                 = %$tb{$reportId}->{'vaccinationDateFixed'} // '';
		my $seriousnessConfirmationRequired      = %$tb{$reportId}->{'seriousnessConfirmationRequired'}     // die;
		$seriousnessConfirmationRequired         = unpack("N", pack("B32", substr("0" x 32 . $seriousnessConfirmationRequired, -32)));
		my $pregnancyDetailsConfirmationRequired = %$tb{$reportId}->{'pregnancyDetailsConfirmationRequired'}     // die;
		$pregnancyDetailsConfirmationRequired    = unpack("N", pack("B32", substr("0" x 32 . $pregnancyDetailsConfirmationRequired, -32)));
		my $pregnancyConfirmationRequired        = %$tb{$reportId}->{'pregnancyConfirmationRequired'}     // die;
		$pregnancyConfirmationRequired           = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmationRequired, -32)));
		if ($menstrualCycleDisordersConfirmation) {
    		$menstrualCycleDisordersConfirmation = unpack("N", pack("B32", substr("0" x 32 . $menstrualCycleDisordersConfirmation, -32)));
			$reports{$vaersId}->{'menstrualCycleDisordersConfirmation'} = $menstrualCycleDisordersConfirmation;
		}
		if ($babyExposureConfirmation) {
    		$babyExposureConfirmation            = unpack("N", pack("B32", substr("0" x 32 . $babyExposureConfirmation, -32)));
			$reports{$vaersId}->{'babyExposureConfirmation'} = $babyExposureConfirmation;
		}
		if ($pregnancyConfirmation) {
    		$pregnancyConfirmation               = unpack("N", pack("B32", substr("0" x 32 . $pregnancyConfirmation, -32)));
			$reports{$vaersId}->{'pregnancyConfirmation'}    = $pregnancyConfirmation;
		}
		if ($seriousnessConfirmation) {
    		$seriousnessConfirmation             = unpack("N", pack("B32", substr("0" x 32 . $seriousnessConfirmation, -32)));
			$reports{$vaersId}->{'seriousnessConfirmation'}  = $seriousnessConfirmation;
		}
		my $patientDiedFixed                     = %$tb{$reportId}->{'patientDiedFixed'};
		if ($patientDiedFixed) {
    		$patientDiedFixed                    = unpack("N", pack("B32", substr("0" x 32 . $patientDiedFixed, -32)));
			$reports{$vaersId}->{'patientDiedFixed'} = $patientDiedFixed;
		}
		my $lifeThreatningFixed                  = %$tb{$reportId}->{'lifeThreatningFixed'};
		if ($lifeThreatningFixed) {
    		$lifeThreatningFixed                 = unpack("N", pack("B32", substr("0" x 32 . $lifeThreatningFixed, -32)));
			$reports{$vaersId}->{'lifeThreatningFixed'} = $lifeThreatningFixed;
		}
		my $permanentDisabilityFixed             = %$tb{$reportId}->{'permanentDisabilityFixed'};
		if ($permanentDisabilityFixed) {
    		$permanentDisabilityFixed            = unpack("N", pack("B32", substr("0" x 32 . $permanentDisabilityFixed, -32)));
			$reports{$vaersId}->{'permanentDisabilityFixed'} = $permanentDisabilityFixed;
		}
		my $hospitalizedFixed                    = %$tb{$reportId}->{'hospitalizedFixed'};
		if ($hospitalizedFixed) {
    		$hospitalizedFixed                   = unpack("N", pack("B32", substr("0" x 32 . $hospitalizedFixed, -32)));
			$reports{$vaersId}->{'hospitalizedFixed'} = $hospitalizedFixed;
		}
		my $childDied                            = %$tb{$reportId}->{'childDied'};
		if ($childDied) {
    		$childDied                           = unpack("N", pack("B32", substr("0" x 32 . $childDied, -32)));
			$reports{$vaersId}->{'childDied'}    = $childDied;
		}
		my $childSeriousAE                       = %$tb{$reportId}->{'childSeriousAE'};
		if ($childSeriousAE) {
    		$childSeriousAE                      = unpack("N", pack("B32", substr("0" x 32 . $childSeriousAE, -32)));
			$reports{$vaersId}->{'childSeriousAE'} = $childSeriousAE;
		}
		my $hoursBetweenVaccineAndAE             = %$tb{$reportId}->{'hoursBetweenVaccineAndAE'};
		my $motherAgeFixed                       = %$tb{$reportId}->{'motherAgeFixed'};
		my $childAgeWeekFixed                    = %$tb{$reportId}->{'childAgeWeekFixed'};
		$reports{$vaersId}->{'reportId'}                             = $reportId;
		$reports{$vaersId}->{'vaccinationDateFixed'}                 = $vaccinationDateFixed;
		$reports{$vaersId}->{'onsetDateFixed'}                       = $onsetDateFixed;
		$reports{$vaersId}->{'seriousnessConfirmationRequired'}      = $seriousnessConfirmationRequired;
		$reports{$vaersId}->{'pregnancyDetailsConfirmationRequired'} = $pregnancyDetailsConfirmationRequired;
		$reports{$vaersId}->{'pregnancyConfirmationRequired'}        = $pregnancyConfirmationRequired;
		$reports{$vaersId}->{'hoursBetweenVaccineAndAE'}             = $hoursBetweenVaccineAndAE;
		$reports{$vaersId}->{'motherAgeFixed'}                       = $motherAgeFixed;
		$reports{$vaersId}->{'childAgeWeekFixed'}                    = $childAgeWeekFixed;

		$hospitalizedFixed        = 0 if !defined $hospitalizedFixed;
		$hoursBetweenVaccineAndAE = 0 if !defined $hoursBetweenVaccineAndAE;
		$pregnancyConfirmation    = 0 if !defined $pregnancyConfirmation;
		$seriousnessConfirmation  = 0 if !defined $seriousnessConfirmation;
		say $out "$vaersId;$pregnancyConfirmation;$seriousnessConfirmation;$patientDiedFixed;$hospitalizedFixed;$lifeThreatningFixed;$permanentDisabilityFixed;$childDied;$vaccinationDateFixed;$onsetDateFixed;$hoursBetweenVaccineAndAE;";
	}
	# p%reports;
	# die;
	close $out;
}

sub parse_states {
	open my $in, '<:utf8', $statesFile;
	while (<$in>) {
		chomp $_;
		my ($sNum, $sCode2, $sName) = split ';', $_;
		die if exists $statesCodes{$sCode2};
		die "missing state in the database : [$sName]. make sure you have run [task/cdc/parse_cdc_archive.pl] first." unless exists $cdcStates{$sName}->{'cdcStateId'};
		$statesCodes{$sCode2}->{'stateName'}  = $sName;
		$statesCodes{$sCode2}->{'internalId'} = $sNum;
	}
	close $in;
}

sub parse_vaers_years {
	for my $filePath (glob "$vaersFolder/*") {
		(my $file  = $filePath) =~ s/raw_data\/AllVAERSDataCSVS\///;
		next unless $file =~ /^....VAERS.*/;
		my ($year) = $file =~ /(....)/; 
		# say "filePath : $filePath";
		# say "file     : $file";
		# say "year     : $year";
		$years{$year} = 1;
	}
	unless (keys %years) {
		say "Missing VAERS data in [$vaersFolder].";
		say "You must download it & unzip it, then place the .csv files in [$vaersFolder].";
		say "Exiting.";
		exit;
	}
}

sub parse_yearly_data {
	for my $year (sort{$a <=> $b} keys %years) {
		next if $year < $fromYear;

		# Configuring expected files ; dying if they aren't found.
		my $dataFile      = "$vaersFolder/$year" . 'VAERSDATA.csv';
		my $symptomsFile  = "$vaersFolder/$year" . 'VAERSSYMPTOMS.csv';
		my $vaccinesFile  = "$vaersFolder/$year" . 'VAERSVAX.csv';
		die "missing mandatory file for year [$year] in [$vaersFolder]" if !-f $dataFile || !-f $symptomsFile || !-f $vaccinesFile;
		my @files = ($dataFile, $symptomsFile, $vaccinesFile);
		for my $filename (@files) {
			my $fileStats = stat($filename);
			$vaersStatistics{'archiveSize'} += $fileStats->size;
		}
		say "dataFile     : $dataFile";
		say "symptomsFile : $symptomsFile";
		say "vaccinesFile : $vaccinesFile";
		say "year         : $year";
		say "*" x 50;

		# Fetching notices - reactions relations.
		my %reportsVaccines = parse_report_vaccine_relations($vaccinesFile);

		# Fetching notices - reactions relations.
		my %reportsSymptoms = parse_report_symptoms_relatons($symptomsFile);
		# p%reportsSymptoms;
		# die;

		# Fetching notices.
		my $expectedValues  = ();
		open my $dataIn, '<:', $dataFile;
		my $utf8DataFile    = "$vaersFolder/$year" . 'VAERSDATA_utf8.csv';
		my $dRNum           = 0;
		my %dataLabels      = ();
		my $dataCsv         = Text::CSV_XS->new ({ binary => 1 });
		while (<$dataIn>) {
			$dRNum++;

			# Fixing some poor encodings, replacing special chars by their UTF8 equivalents.
			$_ =~ s/–/-/g;
			$_ =~ s/–/-/g;
			$_ =~ s/ –D/ -D/g;
			$_ =~ s/\\xA0//g;
			$_ =~ s/~/--:--/g;
			$_ =~ s/ / /g;
			$_ =~ s/\r//g;
			$_ =~ s/[\x{80}-\x{FF}\x{1C}\x{02}\x{05}\x{06}\x{7F}\x{17}\x{10}]//g;
			$_ =~ s/\x{1F}/./g;

			# Verifies that the line now fits UTF-8 standards.
			my $line = verify_line($_);

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
				my $vaersId               = $values{'VAERS_ID'}                   // die;
				my $vaersReceptionDate    = $values{'RECVDATE'}                   // die;
				my $sCode2                = $values{'STATE'}                      // die;
				my $stateName             = $statesCodes{$sCode2}->{'stateName'}  // "Unknown";
				my $stateInternalId       = $statesCodes{$sCode2}->{'internalId'} // "00";
				my $patientAge            = $values{'AGE_YRS'}                    // die;
				my ($vaersAgeInternalId,
					$vaersAgeName)        = age_to_age_group($patientAge);
				my $vaersSexInternalId    = $values{'SEX'}                            // die;
				my $vaersSexName;
				if ($vaersSexInternalId eq 'F') {
					$vaersSexName = 'Female';
				} elsif ($vaersSexInternalId eq 'M') {
					$vaersSexName = 'Male';
				} elsif ($vaersSexInternalId eq 'U') {
					$vaersSexName = 'Unknown';
				} else {
					die "vaersSexInternalId : $vaersSexInternalId";
				}
				my $vaccinationDate               = $values{'VAX_DATE'};
				my $onsetDate                     = $values{'ONSET_DATE'};
				my $deceasedDate                  = $values{'DATEDIED'};
				my $aEDescription                 = $values{'SYMPTOM_TEXT'};
				my $vaersVaccineAdministrator     = $values{'V_ADMINBY'};
				my $vaersVaccineAdministratorName = administrator_to_enum($vaersVaccineAdministrator);
				my $hospitalized                  = $values{'HOSPITAL'};
				my $permanentDisability           = $values{'DISABLE'};
				my $lifeThreatning                = $values{'L_THREAT'};
				my $patientDied                   = $values{'DIED'};
				my $birthDefect                   = $values{'BIRTH_DEFECT'};

				# Converting values to easier to handle formats.
				$patientAge                       = undef unless defined $patientAge      && length $patientAge          >= 1;
				$hospitalized                     = 0 unless defined $hospitalized        && length $hospitalized        >= 1;
				$birthDefect                      = 0 unless defined $birthDefect         && length $birthDefect         >= 1;
				$permanentDisability              = 0 unless defined $permanentDisability && length $permanentDisability >= 1;
				$lifeThreatning                   = 0 unless defined $lifeThreatning      && length $lifeThreatning      >= 1;
				$patientDied                      = 0 unless defined $patientDied         && length $patientDied         >= 1;
				$patientDied                      = 1 if defined $patientDied             && $patientDied         eq 'Y';
				$hospitalized                     = 1 if defined $hospitalized            && $hospitalized        eq 'Y';
				$birthDefect                      = 1 if defined $birthDefect             && $birthDefect         eq 'Y';
				$permanentDisability              = 1 if defined $permanentDisability     && $permanentDisability eq 'Y';
				$lifeThreatning                   = 1 if defined $lifeThreatning          && $lifeThreatning      eq 'Y';
			    $vaersReceptionDate               = convert_date($vaersReceptionDate);
			    my ($vaersReceptionYear,
			    	$vaersReceptionMonth)         = split '-', $vaersReceptionDate;
			    $vaccinationDate                  = convert_date($vaccinationDate) if $vaccinationDate;
			    $deceasedDate                     = convert_date($deceasedDate)    if $deceasedDate;
			    $onsetDate                        = convert_date($onsetDate)       if $onsetDate;

			    # Increments the total of reports here.
				$vaersStatistics{'totalVAERSReports'}++;

				#########################################################
				# Reviewing potential exclusions                        #
				#########################################################
				# If we have no vaccine related to the report, skipping it.
				unless (exists $reportsVaccines{$vaersId}) {
					$vaersStatistics{'exclusions'}->{'noVaccineVAERSReports'}++;
					next;
				}

				# If we have no symptom related to the report, skipping it.
				unless (exists $reportsSymptoms{$vaersId}) {
					$vaersStatistics{'exclusions'}->{'noSymptomsVAERSReports'}++;
					next;
				}

				# If we have no description, skipping it.
				unless ($aEDescription) {
					$vaersStatistics{'exclusions'}->{'noAEDescriptionVAERSReports'}++;
					next;
				}

				# If we have no COVID vaccine, skipping the report.
				my $hasCovidVaccine  = 0;
				my %vaccines = ();
				my $vaccineShortName;
				for my $vaccineData (@{$reportsVaccines{$vaersId}}) {
					# p$vaccineData;
					# die;
					my $vaersVaccineShortName = %$vaccineData{'vaersVaccineShortName'} || next;
					$vaccineShortName         = $vaersVaccineShortName;
					my $dose                  = %$vaccineData{'dose'}                  // die;
					$vaccines{$vaersVaccineShortName}->{$dose} = 1;
					$hasCovidVaccine = 1;
				}
				$vaersStatistics{'yearlyStats'}->{$vaersReceptionYear}->{'totalReports'}++;
				unless ($hasCovidVaccine == 1) {
					$vaersStatistics{'exclusions'}->{'noCovidVaccineVAERSReports'}++;
					next;
				}
				$vaersStatistics{'yearlyStats'}->{$vaersReceptionYear}->{'covid'}++;

				# If we had an improper vaccine administration (for example, Pfizer then Moderna, skipping it for now).
				if (keys %vaccines > 1) {
					$vaersStatistics{'exclusions'}->{'moreThanOneVaccineVAERSReports'}++;
					next;
				}

				# Scanning report data.
				scan_report_data(
					$patientAge, $vaersAgeName,
					$stateInternalId, $stateName,
					$vaccineShortName, $vaersVaccineAdministrator,
					$vaersVaccineAdministratorName, $patientDied,
					$hospitalized, $lifeThreatning,
					$permanentDisability, $vaersSexName,
					$aEDescription, $vaersId,
					$birthDefect, $vaccinationDate,
					$onsetDate, $vaersReceptionDate,
					$deceasedDate, @{$reportsSymptoms{$vaersId}}
				);
			}
		}
		close $dataIn;

		# last; ############ DEBUG.
	}
	say "faulty : $cpt";
}

sub verify_line {
	my $line = shift;

	# Verifying line.
	$line = decode("ascii", $line);
	for (/[^\n -~]/g) {
	    printf "Bad character: %02x\n", ord $_;
	    die;
	}
	return $line;
}

sub parse_report_vaccine_relations {
	my ($vaccinesFile)  = @_;
	my %reportsVaccines = ();
	open my $vaccinesIn, '<:', $vaccinesFile;
	my $vaccinesCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %vaccinesLabels  = ();
	my $dRNum = 0;
	my $expectedValues  = ();
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
		my $line = verify_line($_);

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
			my $dose                  = $values{'VAX_DOSE_SERIES'};
			my $vaersId               = $values{'VAERS_ID'} // die;
			my $vaersManufacturerName = $values{'VAX_MANU'} // die;
			my $vaersVaccineTypeName  = $values{'VAX_TYPE'} // die;
			my $vaersVaccineName      = $values{'VAX_NAME
'} // die;

			# Setting a shortname for the substances we care about.
			my $vaersVaccineShortName = substance_synthesis($vaersVaccineName);
			# say "vaersId             : $vaersId";
			# say "dose                : $dose";
			# say "vaersManufacturerName : $vaersManufacturerName";
			# say "vaersVaccineTypeName  : $vaersVaccineTypeName";
			# say "vaersVaccineName      : $vaersVaccineName";
			my %obj = ();
			$obj{'dose'}                  = $dose;
			$obj{'vaersManufacturerName'} = $vaersManufacturerName;
			$obj{'vaersVaccineShortName'} = $vaersVaccineShortName;
			$obj{'vaersVaccineTypeName'}  = $vaersVaccineTypeName;
			$obj{'vaersVaccineName'}      = $vaersVaccineName;
			push @{$reportsVaccines{$vaersId}}, \%obj;
		}
	}
	close $vaccinesIn;
	return %reportsVaccines;
}

sub parse_report_symptoms_relatons {
	my ($symptomsFile) = @_;

	# Fetching notices - vaccines relations.
	my %reportsSymptoms = ();
	open my $symptomsIn, '<:', $symptomsFile;
	my $symptomsCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %symptomsLabels  = ();
	my $dRNum           = 0;
	my $expectedValues  = ();
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

		# Verifies that the line now fits UTF-8 standards.
		my $line = verify_line($_);

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
			for my $symptomName (@symptoms) {
				next unless $symptomName && length $symptomName >= 1;
				# say "symptomName             : $symptomName";
				my %obj = ();
				$obj{'symptomName'} = $symptomName;
				push @{$reportsSymptoms{$vaersId}}, \%obj;
			}
		}
	}
	close $symptomsIn;
	return %reportsSymptoms;
}

sub scan_report_data {
	my (
		$patientAge, $vaersAgeName,
		$stateInternalId, $stateName,
		$vaccineShortName, $vaersVaccineAdministrator,
		$vaersVaccineAdministratorName, $patientDied,
		$hospitalized, $lifeThreatning,
		$permanentDisability, $vaersSexName,
		$aEDescription, $vaersId,
		$birthDefect, $vaccinationDate,
		$onsetDate, $vaersReceptionDate,
		$deceasedDate, @reportsSymptoms
	) = @_;

	# Indentifying if the report concerns a very young child.
	if ($patientAge && ($patientAge <= 2)) {
		$vaersStatistics{'under2YOPatients'}->{'totalReports'}++;
	}

	# Identifying latest vaersReceptionDate.
	my $vaersReceptionCompdate = $vaersReceptionDate;
	$vaersReceptionCompdate =~ s/\D//g;
	$vaersStatistics{'vaersReceptionCompdate'} = $vaersReceptionCompdate if !exists $vaersStatistics{'vaersReceptionCompdate'};
	if ($vaersReceptionCompdate > $vaersStatistics{'vaersReceptionCompdate'}) {
		$vaersStatistics{'vaersReceptionCompdate'} = $vaersReceptionCompdate;
		$vaersStatistics{'vaersReceptionLastDate'} = $vaersReceptionDate;
	}

	# Building statistics on vaccines.
	if ($patientDied) {
		$vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalDeaths'}++;
	} elsif ($hospitalized || $lifeThreatning || $permanentDisability) {
		$vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalSeriousEvents'}++;
	}
	$vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalReports'}++;

	# Converting vaccine short name to vaersVaccine enum.
	my $vaersVaccine;
	if ($vaccineShortName eq 'MODERNA') {
		$vaersVaccine = 1;
	} elsif ($vaccineShortName eq 'PFIZER-BIONTECH') {
		$vaersVaccine = 2;
	} elsif ($vaccineShortName eq 'JANSSEN') {
		$vaersVaccine = 3;
	} elsif ($vaccineShortName eq 'UNKNOWN') {
		$vaersVaccine = 4;
	} else {
		die;
	}

	# Converting sex name to vaersSex enum.
	my $vaersSex;
	if ($vaersSexName eq 'Female') {
		$vaersSex = 1;
	} elsif ($vaersSexName eq 'Male') {
		$vaersSex = 2;
	} elsif ($vaersSexName eq 'Unknown') {
		$vaersSex = 3;
	} else {
		die;
	}

	# Parsing symptoms, excluding administration errors.
	my $hasExcudedSymptom         = 0;
	my $severePregnancySymptom    = 0;
	my $likelyMiscarriageSymptoms = 0;
	my $hasDirectPregnancySymptom = 0;
	my $hasLikelyPregnancySymptom = 0;
	my @symptomsListed  = ();
	for my $symptomData (@reportsSymptoms) {
		my $symptomName = %$symptomData{'symptomName'} // die;
		unless (exists $allSymptoms{$symptomName}->{'symptomId'}) {
			my $sth = $dbh->prepare("INSERT INTO vaers_fertility_symptom (name) VALUES (?)");
			$sth->execute($symptomName) or die $sth->err();
			vaers_fertility_symptom();
		}
		my $symptomId = $allSymptoms{$symptomName}->{'symptomId'} // die;
		push @symptomsListed, $symptomId;
		if ($excludedSymptoms{$symptomName}->{'symptomId'}) {
			$hasExcudedSymptom  = 1;
		}
		if ($symptomName eq 'Pregnancy' || $symptomName eq 'Exposure during pregnancy' || $symptomName eq 'Maternal exposure during pregnancy') {
			$hasDirectPregnancySymptom = 1;
		}
        if (exists $likelyPregnanciesSymptoms{$symptomName}->{'symptomId'}) {
			$hasLikelyPregnancySymptom = 1;
        }
        if (exists $severePregnanciesSymptoms{$symptomName}->{'symptomId'}) {
			$severePregnancySymptom = 1;
        }
        if (exists $miscarriagePregnanciesSymptoms{$symptomName}->{'symptomId'}) {
			$likelyMiscarriageSymptoms = 1;
        }
	}
	if ($hasExcudedSymptom == 1) {  # Excluding administration errors.
		$vaersStatistics{'exclusions'}->{'excludedSymptomVAERSReport'}++;
		return;
	}

	#########################################################
	# Inconsistencies or Missing Data                       #
	#########################################################
	# Identifying if the sex is missing from the raw report.
	if ($vaersSexName eq 'Unknown') {
		$vaersStatistics{'inconsistencies'}->{'missingSexVAERSReports'}++;
	}

	# Identifying if the patient was potentially pregnant (these will be manually confirmed prior to be integrated to the analysis).
	my $pregnancyConfirmationRequired = 0;
	my $sexWasFixed                   = 0;
	my $normalizedAEDescription       = lc $aEDescription;
	my $isLikelyPregnant  = analyse_pregnancy_characteristics(
																$vaersSexName, $patientAge,
																$hasLikelyPregnancySymptom,
																$hasDirectPregnancySymptom, $birthDefect,
																$normalizedAEDescription, $aEDescription
															  );
	if ($isLikelyPregnant) {
		if ($vaersSexName eq 'Unknown') {
			$vaersStatistics{'inconsistencies'}->{'sexFixedVAERSReports'}++;
			$sexWasFixed  = 1;
			$vaersSexName = 'Female';
		}
		$vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsRequired'}++;
		$pregnancyConfirmationRequired = 1;

		# Categorizing number of events according to VAERS.
		if ($hasDirectPregnancySymptom) {
			$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'vaersPerfectCases'}++;
			$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectCases'}++;
			if ($patientDied == 1) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectDeaths'}++;
			} elsif ($hospitalized || $permanentDisability || $lifeThreatning) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectSeriousesAE'}++;
			}
		} elsif ($hasLikelyPregnancySymptom) {
			$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'vaersApproximateCases'}++;
			$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersApproximateCases'}++;
			if ($patientDied == 1) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersApproximateDeaths'}++;
			} elsif ($hospitalized || $permanentDisability || $lifeThreatning) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersApproximateSeriousesAE'}++;
			}
		}
		if ($hasDirectPregnancySymptom || $hasLikelyPregnancySymptom) {
			$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'vaersPerfectAndApproximateCases'}++;
			$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectAndApproximateCases'}++;
			if ($patientDied == 1) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectAndApproximateDeaths'}++;
			} elsif ($hospitalized || $permanentDisability || $lifeThreatning) {
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'vaersPerfectAndApproximateSeriousesAE'}++;
			}
		}

		# Fetching state id.
		my $cdcStateId = $cdcStates{$stateName}->{'cdcStateId'} // die "stateName : $stateName";

		# Inserting the report treatment data (if required).
		my $symptomsListed = encode_json\@symptomsListed;
		unless (exists $reports{$vaersId}->{'reportId'}) {
			my $sth = $dbh->prepare("
				INSERT INTO vaers_fertility_report (
					vaersId, aEDescription, vaersVaccine, vaersSex, patientAge,
					pregnancyConfirmationRequired, vaersReceptionDate, vaccinationDate, symptomsListed, hospitalized,
					permanentDisability, lifeThreatning, patientDied, hospitalizedFixed, permanentDisabilityFixed,
					lifeThreatningFixed, patientDiedFixed, onsetDate, hasLikelyPregnancySymptom, hasDirectPregnancySymptom, cdcStateId
				) VALUES (
					?, ?, ?, ?, ?,
					1, ?, ?, ?, $hospitalized,
					$permanentDisability, $lifeThreatning, $patientDied, $hospitalized, $permanentDisability,
					$lifeThreatning, $patientDied, ?, $hasLikelyPregnancySymptom, $hasDirectPregnancySymptom,
					?
				)");
			$sth->execute(
				$vaersId, $aEDescription, $vaersVaccine, $vaersSex, $patientAge,
				$vaersReceptionDate, $vaccinationDate, $symptomsListed, $onsetDate, $cdcStateId) or die $sth->err();
			vaers_fertility_report();
		}

		# Flagging the report has being required for pregnancy confirmation.
		my $reportId = $reports{$vaersId}->{'reportId'} // die;
		if (!$reports{$vaersId}->{'pregnancyConfirmationRequired'}) {
			my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET pregnancyConfirmationRequired = 1 WHERE id = $reportId");
			$sth->execute() or die $sth->err();
		}

		my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET cdcStateId = $cdcStateId WHERE id = $reportId");
		$sth->execute() or die $sth->err();

		# If the report has already been processed, extrapolating additional details.
		if (exists $reports{$vaersId}->{'pregnancyConfirmation'}               ||
			exists $reports{$vaersId}->{'menstrualCycleDisordersConfirmation'} ||
			exists $reports{$vaersId}->{'babyExposureConfirmation'}) {
			$vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsPerformed'}++;

			# If the pregnancy has been confirmed, processing data.
			if (exists $reports{$vaersId}->{'pregnancyConfirmation'} && $reports{$vaersId}->{'pregnancyConfirmation'} == 1) {

				# Flagging the report has being required for seriousness confirmation.
				my $reportId = $reports{$vaersId}->{'reportId'} // die;
				if (!$reports{$vaersId}->{'seriousnessConfirmationRequired'}) {
					my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET seriousnessConfirmationRequired = 1 WHERE id = $reportId");
					$sth->execute() or die $sth->err();
				}

				# Incremening VAERS related stats.
				if (!$hasDirectPregnancySymptom && !$hasLikelyPregnancySymptom) {
					$vaersStatistics{'arbitrations'}->{'pregnanciesCompletelyMissed'}++;
					# say "hasDirectPregnancySymptom : $hasDirectPregnancySymptom";
					# say "hasLikelyPregnancySymptom : $hasLikelyPregnancySymptom";
					# die;
				} elsif (!$hasDirectPregnancySymptom && $hasLikelyPregnancySymptom) {
					$vaersStatistics{'arbitrations'}->{'pregnanciesImproperlyTagged'}++;
				}
				$vaersStatistics{'arbitrations'}->{'pregnanciesConfirmed'}++;

				# Categorizing events according to VAERS.
				$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedCases'}++;
				$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedCases'}++;

				# Incrementing stats on reported foetal state.
				if ($likelyMiscarriageSymptoms) {
					$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedChildDeaths'}++;
					$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildDeaths'}++;
				} elsif ($severePregnancySymptom) {
					$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedChildSeriousesAE'}++;
					$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildSeriousesAE'}++;
				}

				# Reporting stats on the mother's state.
				if ($patientDied == 1) {
					$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedDeaths'}++;
					$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedDeaths'}++;
				} elsif ($hospitalized || $permanentDisability || $lifeThreatning) {
					$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedSeriousesAE'}++;
					$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedSeriousesAE'}++;
					if ($permanentDisability) {
						$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedDisabilities'}++;
						$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedDisabilities'}++;
					} elsif ($lifeThreatning) {
						$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedLifeThreats'}++;
						$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedLifeThreats'}++;
					} elsif ($hospitalized) {
						$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedHospitalized'}++;
						$vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedHospitalized'}++;
					}
				}

				# Uncomment this block if you wish to skip most of the tedious "missed abortion" researched.
				# if (!$severePregnancySymptom && !defined $reports{$vaersId}->{'seriousnessConfirmation'} && $normalizedAEDescription !~ /abort/ && $normalizedAEDescription !~ /miscarr/ && $normalizedAEDescription !~ / died/) {
				# 	my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET seriousnessConfirmation = 1, seriousnessConfirmationTimestamp = UNIX_TIMESTAMP() WHERE id = $reportId");
				# 	$sth->execute() or die $sth->err();
				# }

				# If the seriousness has been confirmed, establishing stats based on confirmed seriousness for the foetus.
				if (exists $reports{$vaersId}->{'seriousnessConfirmation'} && $reports{$vaersId}->{'seriousnessConfirmation'} == 1) {
					$vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsPerformed'}++;

					# If the pregnancy has been confirmed as having ended by the child death, processing the mother's age & foetal age.
					if ($reports{$vaersId}->{'childDied'}) {
						#  # else {
						# 	say "*" x 50;
						# 	say "unknown mother's age :";
						# 	say "vaersId                         : $vaersId";
						# 	say "vaersReceptionDate              : $vaersReceptionDate";
						# 	say "vaccinationDate                 : $vaccinationDate";
						# 	say "deceasedDate                    : $deceasedDate";
						# 	say "stateName                       : $stateName";
						# 	say "stateInternalId                 : $stateInternalId";
						# 	say "vaersAgeName                    : $vaersAgeName";
						# 	say "vaersVaccineAdministrator       : $vaersVaccineAdministrator";
						# 	say "vaersVaccineAdministratorName   : $vaersVaccineAdministratorName";
						# 	say "aEDescription                   : $aEDescription";
						# 	say "hospitalized                    : $hospitalized";
						# 	say "permanentDisability             : $permanentDisability";
						# 	say "hasExcudedSymptom               : $hasExcudedSymptom";
						# 	say "hasDirectPregnancySymptom       : $hasDirectPregnancySymptom";
						# 	say "hasLikelyPregnancySymptom       : $hasLikelyPregnancySymptom";
						# 	say "isLikelyPregnant                : $isLikelyPregnant";
						# 	say "severePregnancySymptom          : $severePregnancySymptom";
						# 	say "likelyMiscarriageSymptoms       : $likelyMiscarriageSymptoms";
						# 	say "lifeThreatning                  : $lifeThreatning";
						# 	say "patientDied                     : $patientDied";
						# 	say "vaersSexName                    : $vaersSexName";
						# 	say "sexWasFixed                     : $sexWasFixed";
						# }
						if (!$likelyMiscarriageSymptoms) {
							my %report = ();
				            $report{'vaersId'}                  = $vaersId;
				            $report{'patientAge'}               = $patientAge;
				            $report{'patientDied'}              = $patientDied;
				            $report{'hospitalized'}             = $hospitalized;
				            $report{'lifeThreatning'}           = $lifeThreatning;
				            $report{'vaccinationDate'}          = $vaccinationDate;
				            $report{'onsetDate'}                = $onsetDate;
				            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
				            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
				            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
				            $report{'permanentDisability'}      = $permanentDisability;
				            $report{'stateName'}                = $stateName;
				            $report{'vaersSexName'}             = $vaersSexName;
				            $report{'aEDescription'}            = $aEDescription;
				            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
				            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
				            $report{'vaersVaccineName'}         = $vaccineShortName;
							for my $symptomData (@reportsSymptoms) {
								my $symptomName = %$symptomData{'symptomName'} // die;
				            	$report{'symptoms'}->{$symptomName} = 1;
							}
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'nonFlaggedChildDeaths'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'nonFlaggedChildDeaths'}++;
							$reportsExports{$reportsFolder6}++;
							my $fileNum = $reportsExports{$reportsFolder6} // die;
							open my $out, '>:utf8', "$reportsFolder6/$fileNum.json";
							my $json = encode_json\%report;
							print $out $json;
							close $out;
						}
						my %report = ();
			            $report{'vaersId'}                  = $vaersId;
			            $report{'patientAge'}               = $patientAge;
			            $report{'patientDied'}              = $patientDied;
			            $report{'hospitalized'}             = $hospitalized;
			            $report{'lifeThreatning'}           = $lifeThreatning;
			            $report{'vaccinationDate'}          = $vaccinationDate;
			            $report{'onsetDate'}                = $onsetDate;
			            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
			            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
			            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
			            $report{'permanentDisability'}      = $permanentDisability;
			            $report{'stateName'}                = $stateName;
			            $report{'vaersSexName'}             = $vaersSexName;
			            $report{'aEDescription'}            = $aEDescription;
			            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
			            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
			            $report{'vaersVaccineName'}         = $vaccineShortName;
						for my $symptomData (@reportsSymptoms) {
							my $symptomName = %$symptomData{'symptomName'} // die;
			            	$report{'symptoms'}->{$symptomName} = 1;
						}
						$reportsExports{$reportsFolder7}++;
						my $fileNum = $reportsExports{$reportsFolder7} // die;
						open my $out, '>:utf8', "$reportsFolder7/$fileNum.json";
						my $json = encode_json\%report;
						print $out $json;
						close $out;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildDeaths'}++;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedChildDeaths'}++;
						my $hoursBetweenVaccineAndAE = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
						if (!$hoursBetweenVaccineAndAE && $onsetDate && $vaccinationDate) {
							$hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDate 12:00:00", "$onsetDate 12:00:00");
							$hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
							# say "$vaccinationDate - $onsetDate -> $hoursBetweenVaccineAndAE";
						}
						if ($hoursBetweenVaccineAndAE) {
							my ($vaersTimeGroup, $vaersTimeGroupName) = time_group_from_hours_between_vaccine_and_ae($hoursBetweenVaccineAndAE, $vaersId);
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{$vaersTimeGroup}->{'vaersTimeGroupName'} = $vaersTimeGroupName;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildDeaths'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{$vaersTimeGroup}->{'vaersTimeGroupName'} = $vaersTimeGroupName;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildDeaths'}++;
						} else {
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{'8'}->{'vaersTimeGroupName'} = 'Undetermined Interval';
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{'8'}->{'fixedChildDeaths'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{'8'}->{'vaersTimeGroupName'} = 'Undetermined Interval';
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{'8'}->{'fixedChildDeaths'}++;
						}
					} else {
						if ($likelyMiscarriageSymptoms) {
							my %report = ();
				            $report{'vaersId'}                  = $vaersId;
				            $report{'patientAge'}               = $patientAge;
				            $report{'patientDied'}              = $patientDied;
				            $report{'hospitalized'}             = $hospitalized;
				            $report{'lifeThreatning'}           = $lifeThreatning;
				            $report{'vaccinationDate'}          = $vaccinationDate;
				            $report{'onsetDate'}                = $onsetDate;
				            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
				            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
				            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
				            $report{'permanentDisability'}      = $permanentDisability;
				            $report{'stateName'}                = $stateName;
				            $report{'vaersSexName'}             = $vaersSexName;
				            $report{'aEDescription'}            = $aEDescription;
				            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
				            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
				            $report{'vaersVaccineName'}         = $vaccineShortName;
							for my $symptomData (@reportsSymptoms) {
								my $symptomName = %$symptomData{'symptomName'} // die;
				            	$report{'symptoms'}->{$symptomName} = 1;
							}
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'falsePositiveChildDeaths'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'falsePositiveChildDeaths'}++;
							$reportsExports{$reportsFolder8}++;
							my $fileNum = $reportsExports{$reportsFolder8} // die;
							open my $out, '>:utf8', "$reportsFolder8/$fileNum.json";
							my $json = encode_json\%report;
							print $out $json;
							close $out;
						}
						if ($reports{$vaersId}->{'childSeriousAE'}) {
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildSeriousesAE'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedChildSeriousesAE'}++;
							# my $hoursBetweenVaccineAndAE = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
							# if (!$hoursBetweenVaccineAndAE && $onsetDate && $vaccinationDate) {
							# 	$hoursBetweenVaccineAndAE = time::calculate_minutes_difference("$vaccinationDate 12:00:00", "$onsetDate 12:00:00");
							# 	$hoursBetweenVaccineAndAE = nearest(0.01, ($hoursBetweenVaccineAndAE / 60));
							# 	# say "$vaccinationDate - $onsetDate -> $hoursBetweenVaccineAndAE";
							# }
							# if ($hoursBetweenVaccineAndAE) {
							# 	my ($vaersTimeGroup, $vaersTimeGroupName) = time_group_from_hours_between_vaccine_and_ae($hoursBetweenVaccineAndAE, $vaersId);
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{$vaersTimeGroup}->{'vaersTimeGroupName'} = $vaersTimeGroupName;
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildSeriousesAE'}++;
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{$vaersTimeGroup}->{'vaersTimeGroupName'} = $vaersTimeGroupName;
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildSeriousesAE'}++;
							# } else {
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{'8'}->{'vaersTimeGroupName'} = 'Undetermined Interval';
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byTimeGroup'}->{'8'}->{'fixedChildSeriousesAE'}++;
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{'8'}->{'vaersTimeGroupName'} = 'Undetermined Interval';
							# 	$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byTimeGroup'}->{'8'}->{'fixedChildSeriousesAE'}++;
							# }
						}
						# my $vaersReceptionWeekNumber = time::week_number_from_date($vaersReceptionDate);
						# $vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byReceiptWeek'}->{$vaersReceptionYear}->{$vaersReceptionMonth}->{$vaersReceptionWeekNumber}->{'fixedChildDeaths'}++;
						# $vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'byReceiptWeek'}->{$vaersReceptionYear}->{$vaersReceptionMonth}->{$vaersReceptionWeekNumber}->{'byDates'}->{$vaersReceptionDate}->{'fixedChildDeaths'}++;
						# $vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byReceiptWeek'}->{$vaersReceptionYear}->{$vaersReceptionMonth}->{$vaersReceptionWeekNumber}->{'fixedChildDeaths'}++;
						# $vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'byReceiptWeek'}->{$vaersReceptionYear}->{$vaersReceptionMonth}->{$vaersReceptionWeekNumber}->{'byDates'}->{$vaersReceptionDate}->{'fixedChildDeaths'}++;
					}
					
					# Establishing stats based on confirmed seriousness for the mother.
					$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedCases'}++;
					$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedCases'}++;
					if ($reports{$vaersId}->{'patientDiedFixed'} == 1) {
						my %report = ();
			            $report{'vaersId'}                  = $vaersId;
			            $report{'patientAge'}               = $patientAge;
			            $report{'patientDied'}              = $patientDied;
			            $report{'hospitalized'}             = $hospitalized;
			            $report{'lifeThreatning'}           = $lifeThreatning;
			            $report{'vaccinationDate'}          = $vaccinationDate;
			            $report{'onsetDate'}                = $onsetDate;
			            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
			            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
			            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
			            $report{'permanentDisability'}      = $permanentDisability;
			            $report{'stateName'}                = $stateName;
			            $report{'vaersSexName'}             = $vaersSexName;
			            $report{'aEDescription'}            = $aEDescription;
			            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
			            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
			            $report{'vaersVaccineName'}         = $vaccineShortName;
						for my $symptomData (@reportsSymptoms) {
							my $symptomName = %$symptomData{'symptomName'} // die;
			            	$report{'symptoms'}->{$symptomName} = 1;
						}
						$reportsExports{$reportsFolder4}++;
						my $fileNum = $reportsExports{$reportsFolder4} // die;
						open my $out, '>:utf8', "$reportsFolder4/$fileNum.json";
						my $json = encode_json\%report;
						print $out $json;
						close $out;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedDeaths'}++;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedDeaths'}++;
					} elsif ($reports{$vaersId}->{'hospitalizedFixed'} || $reports{$vaersId}->{'permanentDisabilityFixed'} || $reports{$vaersId}->{'lifeThreatningFixed'}) {
						my %report = ();
			            $report{'vaersId'}                  = $vaersId;
			            $report{'patientAge'}               = $patientAge;
			            $report{'patientDied'}              = $patientDied;
			            $report{'hospitalized'}             = $hospitalized;
			            $report{'lifeThreatning'}           = $lifeThreatning;
			            $report{'vaccinationDate'}          = $vaccinationDate;
			            $report{'onsetDate'}                = $onsetDate;
			            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
			            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
			            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
			            $report{'permanentDisability'}      = $permanentDisability;
			            $report{'stateName'}                = $stateName;
			            $report{'vaersSexName'}             = $vaersSexName;
			            $report{'aEDescription'}            = $aEDescription;
			            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
			            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
			            $report{'vaersVaccineName'}         = $vaccineShortName;
						for my $symptomData (@reportsSymptoms) {
							my $symptomName = %$symptomData{'symptomName'} // die;
			            	$report{'symptoms'}->{$symptomName} = 1;
						}
						$reportsExports{$reportsFolder5}++;
						my $fileNum = $reportsExports{$reportsFolder5} // die;
						open my $out, '>:utf8', "$reportsFolder5/$fileNum.json";
						my $json = encode_json\%report;
						print $out $json;
						close $out;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedSeriousesAE'}++;
						$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedSeriousesAE'}++;
						if ($reports{$vaersId}->{'permanentDisabilityFixed'}) {
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedDisabilities'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedDisabilities'}++;
						} elsif ($reports{$vaersId}->{'lifeThreatningFixed'}) {
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedLifeThreats'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedLifeThreats'}++;
						} elsif ($reports{$vaersId}->{'hospitalizedFixed'}) {
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedHospitalized'}++;
							$vaersStatistics{'seriousesPregnanciesStatistics'}->{$vaccineShortName}->{'fixedHospitalized'}++;
						}
					}

					# Data to posttreat.
					if ($reports{$vaersId}->{'childDied'} || $reports{$vaersId}->{'childSeriousAE'}) {
						# say "*" x 50;
						# say "unknown mother's age :";
						# say "vaersId                         : $vaersId";
						# say "vaersReceptionDate              : $vaersReceptionDate";
						# say "vaccinationDate                 : $vaccinationDate";
						# say "deceasedDate                    : $deceasedDate";
						# say "stateName                       : $stateName";
						# say "stateInternalId                 : $stateInternalId";
						# say "vaersAgeName                    : $vaersAgeName";
						# say "vaersVaccineAdministrator       : $vaersVaccineAdministrator";
						# say "vaersVaccineAdministratorName   : $vaersVaccineAdministratorName";
						# say "aEDescription                   : $aEDescription";
						# say "hospitalized                    : $hospitalized";
						# say "permanentDisability             : $permanentDisability";
						# say "hasExcudedSymptom               : $hasExcudedSymptom";
						# say "hasDirectPregnancySymptom       : $hasDirectPregnancySymptom";
						# say "hasLikelyPregnancySymptom       : $hasLikelyPregnancySymptom";
						# say "isLikelyPregnant                : $isLikelyPregnant";
						# say "severePregnancySymptom          : $severePregnancySymptom";
						# say "likelyMiscarriageSymptoms       : $likelyMiscarriageSymptoms";
						# say "lifeThreatning                  : $lifeThreatning";
						# say "patientDied                     : $patientDied";
						# say "vaersSexName                    : $vaersSexName";
						# say "sexWasFixed                     : $sexWasFixed";
						# say "Enter the mother's age (if known) :";
						# my $motherAge = <STDIN>;
						# chomp $motherAge;

						# say "Enter the foetal age (if known) :";
						# my $childAge = <STDIN>;
						# chomp $childAge;

						# say "Enter the vaccination's occurence compared to the vaccination :";
						if (!$reports{$vaersId}->{'pregnancyDetailsConfirmationRequired'}) {
							unless ($patientAge && $patientAge > 12) { # DEBUG
								my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET pregnancyDetailsConfirmationRequired = 1 WHERE id = $reportId");
								$sth->execute() or die $sth->err();
							}
						}

						# Incrementing age stats.
						if (!$patientAge) {
							$vaersStatistics{'pregnantMothersAges'}->{'mothersAgesMissing'}++;
						}
						if ($reports{$vaersId}->{'motherAgeFixed'}) {
							$vaersStatistics{'pregnantMothersAges'}->{'fixedAges'}++;
						}
						$patientAge = $patientAge || $reports{$vaersId}->{'motherAgeFixed'};

						# Incrementing stats related to child death.
						if ($reports{$vaersId}->{'childDied'}) {
							if ($patientAge) {
								$patientAge = int($patientAge);
								my ($patientAgeGroup, $ageGroupName) = age_group_from_age($patientAge);
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{'TOTALS'}->{'miscarriagesByAges'}->{$patientAgeGroup}->{'fixedChildDeaths'}++;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{'TOTALS'}->{'miscarriagesByAges'}->{$patientAgeGroup}->{'ageGroupName'} = $ageGroupName;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{'TOTALS'}->{'miscarriagesWithAges'}++;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}->{$patientAgeGroup}->{'fixedChildDeaths'}++;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}->{$patientAgeGroup}->{'ageGroupName'} = $ageGroupName;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesWithAges'}++;
								push @{$pregnantMothersAges{'TOTALS'}}, $patientAge;
								push @{$pregnantMothersAges{$vaccineShortName}}, $patientAge;
							} else {
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{'TOTALS'}->{'mothersUnknownAge'}++;
								$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'mothersUnknownAge'}++;
							}

							# Incrementing stats by state.
							$childDeathsByStates{'TOTALS'}->{'fixedChildDeaths'}++;
							$childDeathsByStates{$vaccineShortName}->{'fixedChildDeaths'}++;
							$childDeathsByStates{$vaccineShortName}->{'byStates'}->{$stateName}++;
							$childDeathsByStates{'TOTALS'}->{'byStates'}->{$stateName}++;
						}
					}
				}
				$vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsRequired'}++;
			} else {
				# if ($likelyMiscarriageSymptoms) {
				# 	my $reportId = $reports{$vaersId}->{'reportId'} // die;
				# 	my $sth = $dbh->prepare("UPDATE vaers_fertility_report SET pregnancyConfirmation = NULL, pregnancyConfirmationTimestamp = NULL, menstrualCycleDisordersConfirmation = NULL, menstrualCycleDisordersConfirmationTimestamp = NULL, babyExposureConfirmation = NULL, babyExposureConfirmationTimestamp = NULL, seriousnessConfirmation = NULL, seriousnessConfirmationTimestamp = NULL WHERE id = $reportId");
				# 	$sth->execute() or die $sth->err();

				# 	say "*" x 50;
				# 	say "fixing the following report seriousness :";
				# 	say "vaersReceptionDate              : $vaersReceptionDate";
				# 	say "vaccinationDate                 : $vaccinationDate";
				# 	say "deceasedDate                    : $deceasedDate";
				# 	say "stateName                       : $stateName";
				# 	say "stateInternalId                 : $stateInternalId";
				# 	say "vaersAgeName                    : $vaersAgeName";
				# 	say "vaersVaccineAdministrator       : $vaersVaccineAdministrator";
				# 	say "vaersVaccineAdministratorName   : $vaersVaccineAdministratorName";
				# 	say "aEDescription                   : $aEDescription";
				# 	say "hospitalized                    : $hospitalized";
				# 	say "permanentDisability             : $permanentDisability";
				# 	say "hasExcudedSymptom               : $hasExcudedSymptom";
				# 	say "hasDirectPregnancySymptom       : $hasDirectPregnancySymptom";
				# 	say "hasLikelyPregnancySymptom       : $hasLikelyPregnancySymptom";
				# 	say "isLikelyPregnant                : $isLikelyPregnant";
				# 	say "severePregnancySymptom          : $severePregnancySymptom";
				# 	say "likelyMiscarriageSymptoms       : $likelyMiscarriageSymptoms";
				# 	say "lifeThreatning                  : $lifeThreatning";
				# 	say "patientDied                     : $patientDied";
				# 	say "vaersSexName                    : $vaersSexName";
				# 	say "sexWasFixed                     : $sexWasFixed";
				# 	p$reports{$vaersId};
				# 	$cpt++;
				# 	die; # Verification only, should now be fixed.
				# }
				if ($hasDirectPregnancySymptom || $hasLikelyPregnancySymptom) {
					$vaersStatistics{'arbitrations'}->{'pregnanciesFalseExtrapolation'}++;
					# say "hasDirectPregnancySymptom : $hasDirectPregnancySymptom";
					# say "hasLikelyPregnancySymptom : $hasLikelyPregnancySymptom";
					# die;
				}
				if (exists $reports{$vaersId}->{'menstrualCycleDisordersConfirmation'} && $reports{$vaersId}->{'menstrualCycleDisordersConfirmation'} == 1) {
					$vaersStatistics{'arbitrations'}->{'reproductiveIssuesConfirmed'}++;
				} elsif (exists $reports{$vaersId}->{'babyExposureConfirmation'} && $reports{$vaersId}->{'babyExposureConfirmation'} == 1) {
					$vaersStatistics{'arbitrations'}->{'babiesExposureConfirmed'}++;
				} else {
					$vaersStatistics{'arbitrations'}->{'pregnancyConfirmationFalsePositives'}++;
				}
			}
		}

		# Exporting reports of interest.
		# Requalfiied as pregnancies.
		if ($hasLikelyPregnancySymptom == 0 && $hasDirectPregnancySymptom == 0 && exists $reports{$vaersId}->{'pregnancyConfirmation'} && $reports{$vaersId}->{'pregnancyConfirmation'} == 1) {
			my %report = ();
            $report{'vaersId'}                  = $vaersId;
            $report{'patientAge'}               = $patientAge;
            $report{'patientDied'}              = $patientDied;
            $report{'hospitalized'}             = $hospitalized;
            $report{'lifeThreatning'}           = $lifeThreatning;
            $report{'vaccinationDate'}          = $vaccinationDate;
            $report{'onsetDate'}                = $onsetDate;
            $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
            $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
            $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
            $report{'permanentDisability'}      = $permanentDisability;
            $report{'stateName'}                = $stateName;
            $report{'vaersSexName'}             = $vaersSexName;
            $report{'aEDescription'}            = $aEDescription;
            $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
            $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
            $report{'vaersVaccineName'}         = $vaccineShortName;
			for my $symptomData (@reportsSymptoms) {
				my $symptomName = %$symptomData{'symptomName'} // die;
            	$report{'symptoms'}->{$symptomName} = 1;
			}
			$reportsExports{$reportsFolder1}++;
			my $fileNum = $reportsExports{$reportsFolder1} // die;
			open my $out, '>:utf8', "$reportsFolder1/$fileNum.json";
			my $json = encode_json\%report;
			print $out $json;
			close $out;
		}
	} else {
		if (exists $reports{$vaersId}->{'pregnancyConfirmation'} && $reports{$vaersId}->{'pregnancyConfirmation'} == 1) {
			say "shouldn't happen :";
			my %report = ();
			$vaersStatistics{'arbitrations'}->{'falsePositivePregnancies'}++;
	        $report{'vaersId'}                  = $vaersId;
	        $report{'patientAge'}               = $patientAge;
	        $report{'patientDied'}              = $patientDied;
	        $report{'hospitalized'}             = $hospitalized;
	        $report{'lifeThreatning'}           = $lifeThreatning;
	        $report{'vaccinationDate'}          = $vaccinationDate;
	        $report{'onsetDate'}                = $onsetDate;
	        $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
	        $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
	        $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
	        $report{'permanentDisability'}      = $permanentDisability;
	        $report{'stateName'}                = $stateName;
	        $report{'vaersSexName'}             = $vaersSexName;
	        $report{'aEDescription'}            = $aEDescription;
	        $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
	        $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
	        $report{'vaersVaccineName'}         = $vaccineShortName;
			for my $symptomData (@reportsSymptoms) {
				my $symptomName = %$symptomData{'symptomName'} // die;
	        	$report{'symptoms'}->{$symptomName} = 1;
			}
			p%report;
			die;
		}
	}
	# False positives.
	if (($hasLikelyPregnancySymptom == 1 || $hasDirectPregnancySymptom == 1) && (!exists $reports{$vaersId}->{'pregnancyConfirmation'} || (exists $reports{$vaersId}->{'pregnancyConfirmation'} && $reports{$vaersId}->{'pregnancyConfirmation'} == 0))) {
		my %report = ();
		$vaersStatistics{'arbitrations'}->{'falsePositivePregnancies'}++;
        $report{'vaersId'}                  = $vaersId;
        $report{'patientAge'}               = $patientAge;
        $report{'patientDied'}              = $patientDied;
        $report{'hospitalized'}             = $hospitalized;
        $report{'lifeThreatning'}           = $lifeThreatning;
        $report{'vaccinationDate'}          = $vaccinationDate;
        $report{'onsetDate'}                = $onsetDate;
        $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
        $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
        $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
        $report{'permanentDisability'}      = $permanentDisability;
        $report{'stateName'}                = $stateName;
        $report{'vaersSexName'}             = $vaersSexName;
        $report{'aEDescription'}            = $aEDescription;
        $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
        $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
        $report{'vaersVaccineName'}         = $vaccineShortName;
		for my $symptomData (@reportsSymptoms) {
			my $symptomName = %$symptomData{'symptomName'} // die;
        	$report{'symptoms'}->{$symptomName} = 1;
		}
		$reportsExports{$reportsFolder2}++;
		my $fileNum = $reportsExports{$reportsFolder2} // die;
		open my $out, '>:utf8', "$reportsFolder2/$fileNum.json";
		my $json = encode_json\%report;
		print $out $json;
		close $out;
	}
	# Incorrect tags.
	if (($hasLikelyPregnancySymptom == 1 && $hasDirectPregnancySymptom == 0) && (exists $reports{$vaersId}->{'pregnancyConfirmation'} && $reports{$vaersId}->{'pregnancyConfirmation'} == 1)) {
		my %report = ();
        $report{'vaersId'}                  = $vaersId;
        $report{'patientAge'}               = $patientAge;
        $report{'patientDied'}              = $patientDied;
        $report{'hospitalized'}             = $hospitalized;
        $report{'lifeThreatning'}           = $lifeThreatning;
        $report{'vaccinationDate'}          = $vaccinationDate;
        $report{'onsetDate'}                = $onsetDate;
        $report{'hoursBetweenVaccineAndAE'} = $reports{$vaersId}->{'hoursBetweenVaccineAndAE'};
        $report{'vaccinationDateFixed'}     = $reports{$vaersId}->{'vaccinationDateFixed'};
        $report{'onsetDateFixed'}           = $reports{$vaersId}->{'onsetDateFixed'};
        $report{'permanentDisability'}      = $permanentDisability;
        $report{'stateName'}                = $stateName;
        $report{'vaersSexName'}             = $vaersSexName;
        $report{'aEDescription'}            = $aEDescription;
        $report{'childDied'}                = $reports{$vaersId}->{'childDied'};
        $report{'childSeriousAE'}           = $reports{$vaersId}->{'childSeriousAE'};
        $report{'vaersVaccineName'}         = $vaccineShortName;
		for my $symptomData (@reportsSymptoms) {
			my $symptomName = %$symptomData{'symptomName'} // die;
        	$report{'symptoms'}->{$symptomName} = 1;
		}
		$reportsExports{$reportsFolder3}++;
		my $fileNum = $reportsExports{$reportsFolder3} // die;
		open my $out, '>:utf8', "$reportsFolder3/$fileNum.json";
		my $json = encode_json\%report;
		print $out $json;
		close $out;
	}

}

sub analyse_pregnancy_characteristics {
	my (
		$vaersSexName, $patientAge,
		$hasLikelyPregnancySymptom,
		$hasDirectPregnancySymptom, $birthDefect,
		$normalizedAEDescription, $aEDescription
	) = @_;
	my $isLikelyPregnant = 0;
	if (
		(
			(
				(
					!defined $patientAge || (
						$patientAge && $patientAge <= 65
					)
				) &&
				(
					$normalizedAEDescription =~ /pregnan/                    ||
					$normalizedAEDescription =~ /gestation/                  ||
					$normalizedAEDescription =~ /estimated date of delivery/ ||
					$normalizedAEDescription =~ /estimated delivery date/    ||
					$normalizedAEDescription =~ /estimated due date/         ||
					$aEDescription =~ /EDD/                                  ||
					$aEDescription =~ /DOD/                                  ||
					$normalizedAEDescription =~ /missed AB/                  ||
					$normalizedAEDescription =~ /miscarriage/
				) &&
				$normalizedAEDescription !~ /non-pregnant female patient/                 &&
				$normalizedAEDescription !~ /the patient is not pregnant/                 &&
				$normalizedAEDescription !~ /\. patient is not pregnant/                  &&
				$normalizedAEDescription !~ /\(no pregnant\)/                             &&
				$normalizedAEDescription !~ /\(not pregnant\)/                            &&
				$normalizedAEDescription !~ /\(non-pregnant\)/                            &&
				$normalizedAEDescription !~ /\(pregnant: no\)/                            &&
				$normalizedAEDescription !~ /\(pregnant:no\)/                             &&
				$normalizedAEDescription !~ /\(no pregnancy\)/                            &&
				$normalizedAEDescription !~ /\(not pregnant at the time of vaccination\)/ &&
				$normalizedAEDescription !~ /it was unknown if the patient is pregnant/   &&
				$normalizedAEDescription !~ /this is a literature report/                 &&
				$normalizedAEDescription !~ /this literature report from a physician reporting same event under the same suspect product for .* patients\./
			)
		) || (
			$hasDirectPregnancySymptom || $hasLikelyPregnancySymptom
		)
	) {
		$isLikelyPregnant = 1;
	}
	return $isLikelyPregnant;
}

sub age_to_age_group {
	my ($patientAge) = @_;
	return (0, 'Unknown') unless defined $patientAge && length $patientAge >= 1;
	my ($vaersAgeInternalId, $vaersAgeName);
	if ($patientAge <= 0.16) {
		$vaersAgeInternalId = '1';
		$vaersAgeName       = '0-1 Month';
	} elsif ($patientAge > 0.16 && $patientAge <= 2.9) {
		$vaersAgeInternalId = '2';
		$vaersAgeName = '2 Months - 2 Years';
	} elsif ($patientAge > 2.9 && $patientAge <= 11.9) {
		$vaersAgeInternalId = '3';
		$vaersAgeName = '3-11 Years';
	} elsif ($patientAge > 11.9 && $patientAge <= 17.9) {
		$vaersAgeInternalId = '4';
		$vaersAgeName = '12-17 Years';
	} elsif ($patientAge > 17.9 && $patientAge <= 64.9) {
		$vaersAgeInternalId = '5';
		$vaersAgeName = '18-64 Years';
	} elsif ($patientAge > 64.9 && $patientAge <= 85.9) {
		$vaersAgeInternalId = '6';
		$vaersAgeName = '65-85 Years';
	} elsif ($patientAge > 85.9) {
		$vaersAgeInternalId = '7';
		$vaersAgeName = 'More than 85 Years';
	} else {
		die "patientAge : $patientAge";
	}
	return ($vaersAgeInternalId, $vaersAgeName);
}

sub administrator_to_enum {
	my ($vaersVaccineAdministrator) = @_;
	if ($vaersVaccineAdministrator eq 'MIL') {
		$vaersVaccineAdministrator = 1;
	} elsif ($vaersVaccineAdministrator eq 'OTH') {
		$vaersVaccineAdministrator = 2;
	} elsif ($vaersVaccineAdministrator eq 'PVT') {
		$vaersVaccineAdministrator = 3;
	} elsif ($vaersVaccineAdministrator eq 'PUB') {
		$vaersVaccineAdministrator = 4;
	} elsif ($vaersVaccineAdministrator eq 'UNK') {
		$vaersVaccineAdministrator = 5;
	} elsif ($vaersVaccineAdministrator eq 'PHM') {
		$vaersVaccineAdministrator = 6;
	} elsif ($vaersVaccineAdministrator eq 'WRK') {
		$vaersVaccineAdministrator = 7;
	} elsif ($vaersVaccineAdministrator eq 'SCH') {
		$vaersVaccineAdministrator = 8;
	} elsif ($vaersVaccineAdministrator eq 'SEN') {
		$vaersVaccineAdministrator = 9;
	} else {
		die "vaersVaccineAdministrator : $vaersVaccineAdministrator";
	}
	return $vaersVaccineAdministrator;
}

sub convert_date {
	my ($dt) = @_;
	my ($m, $d, $y) = split "\/", $dt;
	die unless defined $d && defined $m && defined $y;
	$m = "0$m" if defined $m && $m < 10 && length $m < 2;
	$d = "0$d" if defined $d && $d < 10 && length $d < 2;
	return "$y-$m-$d";
}

sub substance_synthesis {
    my ($substanceName) = @_;
    my $vaersVaccineShortName;
    if (
        $substanceName eq 'COVID19 (COVID19 (JANSSEN))'
    ) {
        $vaersVaccineShortName = 'JANSSEN';
    } elsif (
        $substanceName eq 'COVID19 (COVID19 (MODERNA))'
    ) {
        $vaersVaccineShortName = 'MODERNA';
    } elsif (
        $substanceName eq 'COVID19 (COVID19 (PFIZER-BIONTECH))'
    ) {
        $vaersVaccineShortName = 'PFIZER-BIONTECH';
    } elsif ($substanceName eq 'COVID19 (COVID19 (UNKNOWN))') {
        $vaersVaccineShortName = 'UNKNOWN';
    } else {
    	# $unknownSubstances{$substanceName} = 1;
        return 0;
    }
    return ($vaersVaccineShortName);
}

sub time_group_from_hours_between_vaccine_and_ae {
	my ($hoursBetweenVaccineAndAE, $vaersId) = @_;
	my ($vaersTimeGroup, $vaersTimeGroupName);
	if ($hoursBetweenVaccineAndAE >= 0 && $hoursBetweenVaccineAndAE <= 24) {
		$vaersTimeGroup     = 1;
		$vaersTimeGroupName = 'Within 24 hours post vaccine';
	} elsif ($hoursBetweenVaccineAndAE > 24 && $hoursBetweenVaccineAndAE <= 48) {
		$vaersTimeGroup     = 2;
		$vaersTimeGroupName = 'Between one & two days post vaccine';
	} elsif ($hoursBetweenVaccineAndAE > 48 && $hoursBetweenVaccineAndAE <= 168) {
		$vaersTimeGroup     = 3;
		$vaersTimeGroupName = 'Between two & seven days post vaccine'
	} elsif ($hoursBetweenVaccineAndAE > 168 && $hoursBetweenVaccineAndAE <= 336) {
		$vaersTimeGroup     = 4;
		$vaersTimeGroupName = 'Between one & two weeks post vaccine'
	} elsif ($hoursBetweenVaccineAndAE > 336 && $hoursBetweenVaccineAndAE <= 672) {
		$vaersTimeGroup     = 5;
		$vaersTimeGroupName = 'Between two weeks & a month post vaccine'
	} elsif ($hoursBetweenVaccineAndAE > 672 && $hoursBetweenVaccineAndAE <= 1344) {
		$vaersTimeGroup     = 6;
		$vaersTimeGroupName = 'Between one month & two monthes post vaccine'
	} elsif ($hoursBetweenVaccineAndAE > 1344) {
		$vaersTimeGroup     = 7;
		$vaersTimeGroupName = 'Over two monthes post vaccine'
	} else {
		die "hoursBetweenVaccineAndAE : $hoursBetweenVaccineAndAE on vaers id [$vaersId]";
	}
	return ($vaersTimeGroup, $vaersTimeGroupName);
}

sub age_group_from_age {
	my ($patientAge) = @_;
	my ($ageGroup, $ageGroupName);
	if ($patientAge >= 10 && $patientAge <= 20) {
		$ageGroup = 1;
		$ageGroupName = '10-20 ans';
	} elsif ($patientAge > 20 && $patientAge <= 30) {
		$ageGroup = 2;
		$ageGroupName = '20-30 ans';
	} elsif ($patientAge > 30 && $patientAge <= 40) {
		$ageGroup = 3;
		$ageGroupName = '30-40 ans';
	} elsif ($patientAge > 40 && $patientAge <= 50) {
		$ageGroup = 4;
		$ageGroupName = '40-50 ans';
	} elsif ($patientAge > 50 && $patientAge <= 60) {
		$ageGroup = 5;
		$ageGroupName = '50-60 ans';
	} else {
		die "patientAge : $patientAge";
	}
	return ($ageGroup, $ageGroupName);
}

sub generate_end_user_stats {
	$vaersStatistics{'archiveSize'} = nearest(0.1, $vaersStatistics{'archiveSize'} / 1000000);
	$vaersStatistics{'archiveSize'} .= " Mo";

	# Generating COVID reports percentage.
	for my $yearName (sort keys %{$vaersStatistics{'yearlyStats'}}) {
		my $covid = $vaersStatistics{'yearlyStats'}->{$yearName}->{'covid'} // die;
		my $totalReports = $vaersStatistics{'yearlyStats'}->{$yearName}->{'totalReports'} // die;
		my $covidPercent = nearest(0.01, $covid * 100 / $totalReports);
		$vaersStatistics{'yearlyStats'}->{$yearName}->{'covidPercent'} = $covidPercent;
	}

	# Generating vaccines deaths & serious events percentages of total AE reported.
	for my $vaccineShortName (sort keys %{$vaersStatistics{'vaccineStatitics'}}) {
		my $totalDeaths = $vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalDeaths'} // 0;
		my $totalReports = $vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalReports'} // die;
		my $totalDeathsPercent = nearest(0.01, $totalDeaths * 100 / $totalReports);
		$vaersStatistics{'vaccineStatitics'}->{$vaccineShortName}->{'totalDeathsPercent'} = $totalDeathsPercent;
	}

	# Generating vaccines deaths & serious events percentages of total AE reported.
	my @statLabels = ('seriousesPregnanciesStatistics', 'pregnanciesStatistics');
	for my $statLabel (@statLabels) {
		for my $vaccineShortName (sort keys %{$vaersStatistics{$statLabel}}) {
			my $fixedDeaths               = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedDeaths'}           // 0;
			my $fixedSeriousesAE          = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedSeriousesAE'}      // 0;
			my $fixedCases                = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedCases'}            // 0;
			my $fixedHospitalized         = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedHospitalized'}     // 0;
			my $fixedDisabilities         = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedDisabilities'}     // 0;
			my $fixedLifeThreats          = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedLifeThreats'}      // 0;
			my $fixedChildDeaths          = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedChildDeaths'}      // 0;
			my $fixedChildSeriousesAE     = $vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedChildSeriousesAE'} // 0;
			my ($fixedDeathsPercent, $fixedSeriousesAEPercent, $fixedHospitalizedPercent, $fixedDisabilitiesPercent, $fixedLifeThreatsPercent, $fixedChildDeathsPercent, $fixedChildSeriousesAEPercent) = (0, 0, 0, 0, 0, 0, 0);
			if ($fixedCases) {
				$fixedDeathsPercent           = nearest(0.01, $fixedDeaths           * 100 / $fixedCases);
				$fixedSeriousesAEPercent      = nearest(0.01, $fixedSeriousesAE      * 100 / $fixedCases);
				$fixedHospitalizedPercent     = nearest(0.01, $fixedHospitalized     * 100 / $fixedCases);
				$fixedDisabilitiesPercent     = nearest(0.01, $fixedDisabilities     * 100 / $fixedCases);
				$fixedLifeThreatsPercent      = nearest(0.01, $fixedLifeThreats      * 100 / $fixedCases);
				$fixedChildSeriousesAEPercent = nearest(0.01, $fixedChildSeriousesAE * 100 / $fixedCases);
				$fixedChildDeathsPercent      = nearest(0.01, $fixedChildDeaths      * 100 / $fixedCases);
			}
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedDeathsPercent'}           = $fixedDeathsPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedSeriousesAEPercent'}      = $fixedSeriousesAEPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedHospitalizedPercent'}     = $fixedHospitalizedPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedDisabilitiesPercent'}     = $fixedDisabilitiesPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedLifeThreatsPercent'}      = $fixedLifeThreatsPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedChildDeathsPercent'}      = $fixedChildDeathsPercent;
			$vaersStatistics{$statLabel}->{$vaccineShortName}->{'fixedChildSeriousesAEPercent'} = $fixedChildSeriousesAEPercent;

			# Calculating offsets if required.
			if ($statLabel eq 'seriousesPregnanciesStatistics') {
				my $originalFixedDeaths           = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedDeaths'}           // 0;
				my $originalFixedDisabilities     = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedDisabilities'}     // 0;
				my $originalFixedLifeThreats      = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedLifeThreats'}      // 0;
				my $originalFixedHospitalized     = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedHospitalized'}     // 0;
				my $originalFixedSeriousesAE      = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedSeriousesAE'}      // 0;
				my $originalFixedChildDeaths      = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildDeaths'}      // 0;
				my $originalFixedChildSeriousesAE = $vaersStatistics{'pregnanciesStatistics'}->{$vaccineShortName}->{'fixedChildSeriousesAE'} // 0;
				my $offsetChildDeathsPercent      = 0;

				my $offsetDeaths           = $fixedDeaths           - $originalFixedDeaths;
				my $offsetLifeThreats      = $fixedLifeThreats      - $originalFixedLifeThreats;
				my $offsetDisabilities     = $fixedDisabilities     - $originalFixedDisabilities;
				my $offsetHospitalized     = $fixedHospitalized     - $originalFixedHospitalized;
				my $offsetSeriousesAE      = $fixedSeriousesAE      - $originalFixedSeriousesAE;
				my $offsetChildDeaths      = $fixedChildDeaths      - $originalFixedChildDeaths;
				my $offsetChildSeriousesAE = $fixedChildSeriousesAE - $originalFixedChildSeriousesAE;
				if ($fixedChildDeaths) {
					$offsetChildDeathsPercent = nearest(0.01, $offsetChildDeaths * 100 / $fixedChildDeaths);
				}
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetDeaths'}             = $offsetDeaths;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetLifeThreats'}        = $offsetLifeThreats;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetDisabilities'}       = $offsetDisabilities;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetHospitalized'}       = $offsetHospitalized;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetSeriousesAE'}        = $offsetSeriousesAE;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetChildDeaths'}        = $offsetChildDeaths;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetChildDeathsPercent'} = $offsetChildDeathsPercent;
				$vaersStatistics{$statLabel}->{$vaccineShortName}->{'offsetChildSeriousesAE'}   = $offsetChildSeriousesAE;
			}
		}
	}

	# Fetching percentages of arbitrations.
	if (exists $vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsRequired'}) {
		my $pregnanciesConfirmationsPerformed = $vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsPerformed'}   // die;
		my $pregnanciesConfirmationsRequired  = $vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsRequired'} // die;
		my $pregnanciesConfirmationsPerformedPercent = nearest(0.01, $pregnanciesConfirmationsPerformed * 100 / $pregnanciesConfirmationsRequired);
		$vaersStatistics{'arbitrations'}->{'pregnanciesConfirmationsPerformedPercent'} = $pregnanciesConfirmationsPerformedPercent;
	}
	if (exists $vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsRequired'}) {
		my $pregnanciesSeriousnessConfirmationsPerformed = $vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsPerformed'} // die;
		my $pregnanciesSeriousnessConfirmationsRequired  = $vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsRequired'}  // die;
		my $pregnanciesSeriousnessConfirmationsPerformedPercent = nearest(0.01, $pregnanciesSeriousnessConfirmationsPerformed * 100 / $pregnanciesSeriousnessConfirmationsRequired);
		$vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsPerformedPercent'} = $pregnanciesSeriousnessConfirmationsPerformedPercent;
	}

	# Fetching percentage of qualification errors.
	my $pregnanciesCompletelyMissed   = $vaersStatistics{'arbitrations'}->{'pregnanciesCompletelyMissed'}   // 0;
	my $pregnanciesImproperlyTagged   = $vaersStatistics{'arbitrations'}->{'pregnanciesImproperlyTagged'}   // 0;
	my $pregnanciesFalseExtrapolation = $vaersStatistics{'arbitrations'}->{'pregnanciesFalseExtrapolation'} // 0;
	my $qualificationErrors           = $pregnanciesCompletelyMissed + $pregnanciesImproperlyTagged + $pregnanciesFalseExtrapolation;
	$vaersStatistics{'arbitrations'}->{'qualificationErrors'} = $qualificationErrors;

	# Fetching percentages of child deaths & serious AES.
	if ($vaersStatistics{'seriousesPregnanciesStatistics'}->{'TOTALS'}->{'fixedChildDeaths'}) {
		for my $label (sort keys %{$vaersStatistics{'seriousesPregnanciesStatistics'}}) {
			my $globalTotalMiscarriages  = $vaersStatistics{'seriousesPregnanciesStatistics'}->{$label}->{'fixedChildDeaths'} // 0;
			my $pregnanciesSeriousnessConfirmationsPerformed = $vaersStatistics{'arbitrations'}->{'pregnanciesSeriousnessConfirmationsPerformed'} // die;
			$vaersStatistics{'seriousesPregnanciesStatistics'}->{$label}->{'fixedChildDeathsPercent'} = nearest(0.01, $globalTotalMiscarriages * 100 / $pregnanciesSeriousnessConfirmationsPerformed);
			for my $vaersTimeGroup (sort{$a <=> $b} keys %{$vaersStatistics{'seriousesPregnanciesStatistics'}->{$label}->{'byTimeGroup'}}) {
				my $fixedChildDeaths = $vaersStatistics{'seriousesPregnanciesStatistics'}->{$label}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildDeaths'} // 0;
				my $fixedChildDeathsPercent = nearest(0.01, $fixedChildDeaths * 100 / $globalTotalMiscarriages);
				$vaersStatistics{'seriousesPregnanciesStatistics'}->{$label}->{'byTimeGroup'}->{$vaersTimeGroup}->{'fixedChildDeathsPercent'} = $fixedChildDeathsPercent;
			}
		}
	}

	# Fetching offsets on fixed / vaers values for the total pregnancies cases.
  	my $janssenVaersCases  = $vaersStatistics{'pregnanciesStatistics'}->{'JANSSEN'}->{'vaersPerfectAndApproximateCases'}         // 0;
  	my $modernaVaersCases  = $vaersStatistics{'pregnanciesStatistics'}->{'MODERNA'}->{'vaersPerfectAndApproximateCases'}         // 0;
  	my $pfizerVaersCases   = $vaersStatistics{'pregnanciesStatistics'}->{'PFIZER-BIONTECH'}->{'vaersPerfectAndApproximateCases'} // 0;
  	my $unknownVaersCases  = $vaersStatistics{'pregnanciesStatistics'}->{'UNKNOWN'}->{'vaersPerfectAndApproximateCases'}         // 0;
  	my $totalVaersCases    = $vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'vaersPerfectAndApproximateCases'}          // 0;
  	my $janssenFixedCases  = $vaersStatistics{'pregnanciesStatistics'}->{'JANSSEN'}->{'fixedCases'}         // 0;
  	my $modernaFixedCases  = $vaersStatistics{'pregnanciesStatistics'}->{'MODERNA'}->{'fixedCases'}         // 0;
  	my $pfizerFixedCases   = $vaersStatistics{'pregnanciesStatistics'}->{'PFIZER-BIONTECH'}->{'fixedCases'} // 0;
  	my $unknownFixedCases  = $vaersStatistics{'pregnanciesStatistics'}->{'UNKNOWN'}->{'fixedCases'}         // 0;
  	my $totalFixedCases    = $vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'fixedCases'}          // 0;
  	my $totalCasesOffset   = $totalFixedCases   - $totalVaersCases;
  	my $janssenCasesOffset = $janssenFixedCases - $janssenVaersCases;
  	my $modernaCasesOffset = $modernaFixedCases - $modernaVaersCases;
  	my $pfizerCasesOffset  = $pfizerFixedCases  - $pfizerVaersCases;
  	my $unknownCasesOffset = $unknownFixedCases - $unknownVaersCases;
  	$vaersStatistics{'pregnanciesStatistics'}->{'TOTALS'}->{'totalCasesOffset'}           = $totalCasesOffset;
  	$vaersStatistics{'pregnanciesStatistics'}->{'JANSSEN'}->{'janssenCasesOffset'}        = $janssenCasesOffset;
  	$vaersStatistics{'pregnanciesStatistics'}->{'MODERNA'}->{'modernaCasesOffset'}        = $modernaCasesOffset;
  	$vaersStatistics{'pregnanciesStatistics'}->{'PFIZER-BIONTECH'}->{'pfizerCasesOffset'} = $pfizerCasesOffset;
  	$vaersStatistics{'pregnanciesStatistics'}->{'UNKNOWN'}->{'unknownCasesOffset'}        = $unknownCasesOffset;

  	# Finalizing statistics on mothers ages.
  	if (exists $vaersStatistics{'pregnantMothersAgesStatistics'}) {
  		for my $vaccineShortName (sort keys %{$vaersStatistics{'pregnantMothersAgesStatistics'}}) {
			my $miscarriagesWithAges = $vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesWithAges'} // die;

  			# Calculating min, max, median, mean.
  			my @ages = @{$pregnantMothersAges{$vaccineShortName}};
			my $n    = 0;
			my $sum  = 0;
			for my $age (@ages) {
       			$n++;
		        $sum += $age;
			}
			die "no values" if $n == 0 || $n != $miscarriagesWithAges;
			my $ageMean = nearest(0.1, $sum / $n);
			my $sqsum = 0;
			for (@ages) {
			    $sqsum += ( $_ ** 2 );
			} 
			$sqsum /= $n;
			$sqsum -= ( $ageMean ** 2 );
			my $ageMedian = median_from_array(@ages);
			my $ageMin = min @ages;
			my $ageMax = max @ages;
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageMedian'} = $ageMedian;
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageMean'}   = $ageMean;
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageMin'}    = $ageMin;
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageMax'}    = $ageMax;
			# printf "n is %d, min is %g, max is %g\n", $n, $ageMin, $ageMax;
			# printf "median is %g, mean is %g\n", 
			#     $mode, $ageMedian, $ageMean;

			# Having the median, we calculate Q1 & Q3.
			my @firstHalf = ();
			my @secondHalf = ();
			for my $age (@ages) {
				if ($age <= $ageMedian) {
					push @firstHalf, $age;
				}
				if ($age >= $ageMedian) {
					push @secondHalf, $age;
				}
			}
			my $ageQ1 = median_from_array(@firstHalf);
			my $ageQ3 = median_from_array(@secondHalf);
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageQ1'}     = $ageQ1;
			$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'ageQ3'}     = $ageQ3;
  			for my $ageGroup (sort keys %{$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}}) {
  				my $ageGroupName         = $vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}->{$ageGroup}->{'ageGroupName'}     // die;
  				my $fixedChildDeaths     = $vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}->{$ageGroup}->{'fixedChildDeaths'} // 0;
  				my $childDeathsPercent   = nearest(0.01, $fixedChildDeaths * 100 / $miscarriagesWithAges);
  				$vaersStatistics{'pregnantMothersAgesStatistics'}->{$vaccineShortName}->{'miscarriagesByAges'}->{$ageGroup}->{'childDeathsPercent'} = $childDeathsPercent;

  			}
  		}
  	}
  	for my $vaccineShortName (sort keys %childDeathsByStates) {
  		my $fixedChildDeaths = $childDeathsByStates{$vaccineShortName}->{'fixedChildDeaths'} // die;
	  	for my $stateName (sort keys %{$childDeathsByStates{$vaccineShortName}->{'byStates'}}) {
	  		my $stateChildrenDeaths = $childDeathsByStates{$vaccineShortName}->{'byStates'}->{$stateName} // die;
	  		my $stateChildrenDeathsPercent = nearest(0.01, $stateChildrenDeaths * 100 / $fixedChildDeaths);
			$vaersStatistics{'statesChildrenDeaths'}->{$vaccineShortName}->{'vaccineChildrenDeaths'} += $stateChildrenDeaths;
			$vaersStatistics{'statesChildrenDeaths'}->{$vaccineShortName}->{'byDeaths'}->{$stateChildrenDeaths}->{'stateChildrenDeathsPercent'} = $stateChildrenDeathsPercent;
			$vaersStatistics{'statesChildrenDeaths'}->{$vaccineShortName}->{'byDeaths'}->{$stateChildrenDeaths}->{'states'}->{$stateName} = 1;
	  	}
  	}
	make_path('stats') unless (-d 'stats');
	my $vaersStatisticsJson = encode_json\%vaersStatistics;
	open my $out, '>:utf8', 'stats/vaers_fertility_study.json';
	print $out $vaersStatisticsJson;
	close $out;

	# open my $out, '>:utf8', 'unknown_symptoms.txt';
	# for my $symptomName (sort keys %unknownSymptoms) {
	# 	say $out $symptomName;
	# }
	# close $out;
	# p%unknownSymptoms;

}

sub by_number {
    if ($a < $b){ -1 } elsif ($a > $b) { 1 } else { 0 }
}

sub median_from_array {
	my (@ages) = @_;
	my $mid = int @ages/2;
	my @sortedValues = sort by_number @ages;
	my $ageMedian;
	if (@ages % 2) {
	    $ageMedian = $sortedValues[ $mid ];
	} else {
	    $ageMedian = ($sortedValues[$mid-1] + $sortedValues[$mid]) / 2;
	}
	return $ageMedian;
}

__END__


# Following code has been written to add extrapolations to the reports ; but isn't ready to be integrated in the study yet.
sub additional_report_parsing {
				
	# Verifying potential errors on vaccination date.
	my ($vaccinationDateError, $vaccinationDateManualReview, $vaccinationDateLikelyDOB) = (0, 0, 0);
	if ($vaccinationDate) {
		my ($vaccinationYear, $vaccinationMonth, $vaccinationDay) = split '-', $vaccinationDate;
		if ($vaccinationYear < $fromYear) {
			$vaccinationDateError = 1;
			my ($vaersReceptionYear, $vaersReceptionMonth) = split '-', $vaersReceptionDate;
			if ($vaersReceptionMonth > 3 && $vaersReceptionMonth >= $vaccinationMonth && $patientAge) {

				# Verifying if the vaccination date has been confused with the patient DOB ; overwise considering it has been a typo at conversion stage.
				my $ageInSeconds = $patientAge * 365 * 86400;
				# say "vaersReceptionDate : $vaersReceptionDate";
				my $approximativeDOBDate = time::subtract_seconds_to_datetime("$vaersReceptionDate 12:00:00", $ageInSeconds);
				my ($approximativeDOBYear) = split '-', $approximativeDOBDate;
				my $yearOffSet = abs($vaccinationYear - $approximativeDOBYear);
				if ($yearOffSet <= 1) {
					# say "can't fix date : [$vaccinationYear-$vaccinationMonth-$vaccinationDay] - likely DOB (offset between years : $yearOffSet, approximativeDOBDate : $approximativeDOBDate)";
					$vaccinationDateLikelyDOB = 1;
					$vaccinationDateManualReview = 1;
					$vaersStatistics{'inconsistencies'}->{'vaccinationDateCantBeFixedVAERSReports'}++;
				} else {
					# say "automatically fixing date : [$vaccinationYear-$vaccinationMonth-$vaccinationDay], receipt on [$vaersReceptionDate], patient age : $patientAge, approximativeDOBDate : $approximativeDOBDate";
					$vaccinationDate = "$vaersReceptionYear-$vaccinationMonth-$vaccinationDay";
					# say "---> [$vaccinationDate]";
					$vaersStatistics{'inconsistencies'}->{'vaccinationDateFixedVAERSReports'}++;
				}
			} else {
				# say "can't fix date : [$vaccinationYear-$vaccinationMonth-$vaccinationDay]";
				$vaccinationDateManualReview = 1;
				$vaersStatistics{'inconsistencies'}->{'vaccinationDateCantBeFixedVAERSReports'}++;
			}
		}
	}

	# Verifying potential errors on deceased date.
	my ($deceasedDateError, $deceasedDateManualReview) = (0, 0);
	if ($deceasedDate) {
		my ($deceasedYear, $deceasedMonth, $deceasedDay) = split '-', $deceasedDate;
		if ($deceasedYear < $fromYear) {
			$deceasedDateError = 1;
			my ($vaersReceptionYear, $vaersReceptionMonth) = split '-', $vaersReceptionDate;
			if ($vaersReceptionMonth > 3 && $vaersReceptionMonth >= $deceasedMonth) {
				# say "automatically fixing date : [$deceasedYear-$deceasedMonth-$deceasedDay], receipt on [$vaersReceptionDate], patient age : $patientAge";
				$deceasedDate  = "$vaersReceptionYear-$deceasedMonth-$deceasedDay";
				# say "---> [$vaccinationDate]";
				$vaersStatistics{'inconsistencies'}->{'deceasedDateFixedVAERSReports'}++;
			} else {
				# say "can't fix date : [$deceasedYear-$deceasedMonth-$deceasedDay]";
				$deceasedDateManualReview = 1;
				$vaersStatistics{'inconsistencies'}->{'deceasedDateCantBeFixedVAERSReports'}++;
			}
		}
	} else {
		# Verifying if we can fetch the deceased date from the text if we haven't it.
		my $deceasedDateCouldBeRetrieved = 0;
		if ($patientDied == 1 && !$deceasedDate) {
			$deceasedDateCouldBeRetrieved = 1;
			# say "We have me able to retrieve a deceased date here : [$aEDescription]";
			$vaersStatistics{'inconsistencies'}->{'deceasedDateCouldBeRetrieved'}++;
		}
	}

	# Verifying potential errors on Age.
	my $ageRequiresTextAnalysis = 0;
	my $ageAutomatedFix = 0;
	unless (defined $patientAge) {
		if ($normalizedAEDescription =~ /pfizer first connect/) {
			$vaersStatistics{'inconsistencies'}->{'noAgeOnPfizerFirstConnect'}++;
		}
		if (($normalizedAEDescription =~ /age/ ||
			$normalizedAEDescription =~ /yo/   ||
			$normalizedAEDescription =~ /year/) &&
			$normalizedAEDescription !~ /unknown age/ &&
			$normalizedAEDescription !~ /of unspecified age/ &&
			$normalizedAEDescription !~ /of an unspecified age/ &&
			$normalizedAEDescription !~ /at an unspecified age/ &&
			$normalizedAEDescription !~ /this is a literature report/) {
			my ($potentialAge);
			$ageRequiresTextAnalysis = 1;
			if ($normalizedAEDescription  =~ / .*-year-old/) {
				($potentialAge) = $normalizedAEDescription =~ / (.*)-year-old/;
			} elsif ($normalizedAEDescription =~ / .*-years-old/) {
				($potentialAge) = $normalizedAEDescription =~ / (.*)-years-old/;
			} elsif ($normalizedAEDescription =~ / .* year-old/) {
				($potentialAge) = $normalizedAEDescription =~ / (.*) year-old/;
			} elsif ($normalizedAEDescription =~ /a .* year old/) {
				($potentialAge) = $normalizedAEDescription =~ /a (.*) year old/;
			} elsif ($normalizedAEDescription =~ /age:.*,/) {
				($potentialAge) = $normalizedAEDescription =~ /age:(.*),/;
			} elsif ($normalizedAEDescription =~ / .* month old/) {
				($potentialAge) = $normalizedAEDescription =~ / (.*) month old/;
				if (looks_like_number $potentialAge) {
					$potentialAge = nearest(0.01, $potentialAge / 12);
				} else {
					$potentialAge = undef;
				}
			} else {
				# say "*" x 50;
				# say "vaersReceptionDate              : $vaersReceptionDate";
				# say "vaccinationDate                 : $vaccinationDate";
				# say "deceasedDate                    : $deceasedDate";
				# say "stateName                       : $stateName";
				# say "stateInternalId                 : $stateInternalId";
				# say "vaersAgeName                    : $vaersAgeName";
				# say "vaersVaccineAdministrator       : $vaersVaccineAdministrator";
				# say "vaersVaccineAdministratorName   : $vaersVaccineAdministratorName";
				# say "vaccinationDateError            : $vaccinationDateError";
				# say "vaccinationDateManualReview     : $vaccinationDateManualReview";
				# say "vaccinationDateLikelyDOB        : $vaccinationDateLikelyDOB";
				# say "aEDescription                   : $aEDescription";
				# say "hospitalized                    : $hospitalized";
				# say "permanentDisability             : $permanentDisability";
				# say "ageRequiresTextAnalysis         : $ageRequiresTextAnalysis";
				# say "lifeThreatning                  : $lifeThreatning";
				# say "patientDied                     : $patientDied";
				# say "vaersSexName                    : $vaersSexName";
				# say "sexWasFixed                     : $sexWasFixed";
			}
			if ($potentialAge && looks_like_number $potentialAge) {
				$vaersStatistics{'inconsistencies'}->{'automatedAgeFixedReports'}++;
				$patientAge = $potentialAge;
				$ageAutomatedFix = 1;
			}
		}
		$vaersStatistics{'inconsistencies'}->{'missingAgeVAERSReports'}++;
	}

	# Verifying if the patient may have died but hasn't been tagged.
	my $mayHaveDiedAndNeedsManualReview = 0;
	if ($patientDied == 0) {
		if (
			$aEDescription =~ /died/ ||
			$aEDescription =~ /deceased/ ||
			$aEDescription =~ /dead/
		) {
			$mayHaveDiedAndNeedsManualReview = 1;
			$vaersStatistics{'inconsistencies'}->{'deathsPotentiallyMissedVAERSReports'}++;
			# say "potentially missed 'dead' tag : [$aEDescription]";
		}
	}
}
#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use time;

my $csvSeparator = ';';

my (@adslColumns,
	@adaeColumns);
  
my %adslData       = ();
my %devData        = ();
my %advaData       = ();
my $advaFile       = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $pcrRecordsFile = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $devData        = "public/doc/pfizer_trials/deviations_data_currated.json";
my $symptomsFile   = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $faceFile       = 'public/doc/pfizer_trials/pfizer_face_patients.json';
my $testsRefsFile  = 'public/doc/pfizer_trials/pfizer_di.json';
my $dt19600101     = '1960-01-01 12:00:00';
my $tp19600101     = time::datetime_to_timestamp($dt19600101);
my $cutoffCompdate = '20210313';

my %pcrRecords     = ();
my %stats          = ();
my %symptoms       = ();
my %faces          = ();
my %testsRefs      = ();

set_columns();

load_symptoms();

load_faces();

load_adva();

load_tests_refs();

load_pcr_tests();

load_supp_dv();

load_adsl_data();

load_adae_data();

print_json();

sub set_columns {
	@adslColumns
	= (
		'subjid',
		'usubjid',
		'age',
		'agetr01',
		'agegr1',
		'agegr1n',
		'race',
		'racen',
		'ethnic',
		'ethnicn',
		'arace',
		'aracen',
		'racegr1',
		'racegr1n',
		'sex',
		'sexn',
		'country',
		'saffl',
		'actarm',
		'actarmcd',
		'trtsdt',
		'vax101dt',
		'vax102dt',
		'vax201dt',
		'vax202dt',
		'vax10udt',
		'vax20udt',
		'reactofl',
		'phase',
		'phasen',
		'unblnddt',
		'bmicat',
		'bmicatn',
		'combodfl',
		'covblst',
		'hivfl',
		'x1csrdt',
		'saf1fl',
		'saf2fl',
		'dthdt'
	);
	@adaeColumns
	= (
		'subjid',
		'usubjid',
		'aeser',
		'aestdtc',
		'aestdy',
		'aescong',
		'aesdisab',
		'aesdth',
		'aeshosp',
		'aeslife',
		'aesmie',
		'aemeres',
		'aerel',
		'aereln',
		'astdt',
		'astdtf',
		'aehlgt',
		'aehlt'
	);
}

sub load_adva {
	open my $in, '<:utf8', $advaFile or die "Missing file [$advaFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
	say "[$advaFile] -> subjects : " . keys %advaData;
}

sub load_tests_refs {
	open my $in, '<:utf8', $testsRefsFile or die "Missing file [$testsRefsFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%testsRefs = %$json;
	say "[$testsRefsFile] -> tests    : " . keys %testsRefs;
}

sub load_pcr_tests {
	open my $in, '<:utf8', $pcrRecordsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pcrRecords = %$json;
	# p$pcrRecords{'44441222'};
	say "[$pcrRecordsFile] -> subjects : " . keys %pcrRecords;
}

sub load_supp_dv {
	open my $in, '<:utf8', $devData or die "Missing file [$devData]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%devData = %$json;
	say "[$devData] -> subjects : " . keys %devData;
}

sub load_symptoms {
	open my $in, '<:utf8', $symptomsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%symptoms = %$json;
	say "[$symptomsFile] -> subjects : " . keys %symptoms;
}

sub load_faces {
	open my $in, '<:utf8', $faceFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%faces = %$json;
	# p%faces;
	# die;
	say "[$faceFile] -> subjects : " . keys %faces;
}

sub load_adsl_data {
	my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
	die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
	open my $in, '<:utf8', $adslFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	while (<$in>) {
		chomp $_;
		$dRNum++;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			$line = lc $line;
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$label =~ s/\"//g;
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
			# p%values;
			my $subjid = $values{'subjid'} // die;
			my $unblindingDate;
			for my $adslColumn (@adslColumns) {
				my $value = $values{$adslColumn} // die "adslColumn : [$adslColumn]";
				die if $value =~ /$csvSeparator/;
				# Converting dates.
				if ($value && (
					$adslColumn eq 'vax101dt' ||
					$adslColumn eq 'vax102dt' ||
					$adslColumn eq 'vax201dt' ||
					$adslColumn eq 'vax202dt' ||
					$adslColumn eq 'trtsdt'   ||
					$adslColumn eq 'vax10udt' ||
					$adslColumn eq 'vax20udt' ||
					$adslColumn eq 'unblnddt' ||
					$adslColumn eq 'x1csrdt'  ||
					$adslColumn eq 'dthdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
					if ($adslColumn eq 'unblnddt') {
						($unblindingDate)   = split ' ', $value;
						$unblindingDate     =~ s/\D//g;
					}
				}
				$adslData{$subjid}->{$adslColumn} = $value;
			}
			my $actArm = $advaData{$subjid}->{'actArm'};
			$adslData{$subjid}->{'adva.actarm'} = $actArm;
			if (exists $devData{$subjid}) {
				for my $dvspid (sort keys %{$devData{$subjid}}) {
					$adslData{$subjid}->{'deviations'}->{$dvspid} = \%{$devData{$subjid}->{$dvspid}};
				}
			} else {
				$adslData{$subjid}->{'deviations'} = {};
			}

			# Loading subject's tests.
			subject_central_pcrs_by_visits($subjid);
			subject_local_pcrs_by_visits($subjid);
			subject_central_nbindings_by_visits($subjid);
			subject_symptoms_by_visits($subjid);
		}
	}
	close $in;
	$dRNum--;
	say "ADSL:";
	say "total rows        : $dRNum";
	say "subjects          : " . keys %adslData;
}

sub load_adae_data {
	my $adaeFile   = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv";
	die "you must convert the adae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv] first." unless -f $adaeFile;
	open my $in, '<:utf8', $adaeFile;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	while (<$in>) {
		chomp $_;
		$dRNum++;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			$line = lc $line;
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$label =~ s/\"//g;
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
			my $subjid = $values{'subjid'}  // die;
			die unless exists $adslData{$subjid};
			my $aestdy = $values{'aestdy'}  // die;
			if ($aestdy) {
				die if $aestdy == 999;
			}
			$aestdy    = 999 if length $aestdy == 0;
			for my $adaeColumn (@adaeColumns) {
				my $value = $values{$adaeColumn} // die "adaeColumn : [$adaeColumn]";
				die if $value =~ /$csvSeparator/;
				# Converting dates.
				if ($value && (
					$adaeColumn eq 'astdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
				}
				$adslData{$subjid}->{'adaeRows'}->{$dRNum}->{$adaeColumn} = $value;
			}
		}
	}
	close $in;
	$dRNum--;
	say "ADAE SAEs:";
	say "total rows        : $dRNum";
}

sub print_json {
	open my $out, '>:utf8', 'adverse_effects_raw_data.json';
	print $out encode_json\%adslData;
	close $out;
}

sub subject_central_pcrs_by_visits {
	my ($subjid) = @_;
	for my $visitDate (sort keys %{$pcrRecords{$subjid}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate    =~ s/\D//g;

		my $mborres = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		my $visit = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		if (exists $adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'} && ($adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'} ne $mborres)) {
			next unless $mborres eq 'POS'; # If several conflicting tests on the same date, we only sustain the last positive one.
		}
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'visitdt'}   = $visitDate;
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'}   = $mborres;
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'visitcpdt'} = $visitCompdate;
	}
}

sub subject_local_pcrs_by_visits {
	my ($subjid) = @_;
	for my $visitDate (sort keys %{$pcrRecords{$subjid}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'};
		# p$pcrRecords{$subjid};
		# die;
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		my $mborres   = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'mbResult'} // die;
		my $visitName = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		my $spDevId   = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'spDevId'}  // die;
		my ($deviceType, $tradeName);
		if ($spDevId) {
			die "spDevId: $spDevId" unless $spDevId && looks_like_number $spDevId;
			die unless exists $testsRefs{$spDevId};
			$deviceType = $testsRefs{$spDevId}->{'Device Type'} // die;
			$tradeName  = $testsRefs{$spDevId}->{'Trade Name'}  // die;
			$spDevId = "$deviceType - $tradeName ($spDevId)";
		} else {
			$spDevId = 'Not Provided';
		}
		if ($mborres eq 'POSITIVE') {
			$mborres = 'POS';
		} elsif ($mborres eq 'NEGATIVE') {
			$mborres = 'NEG';
		} elsif ($mborres eq 'INDETERMINATE' || $mborres eq '') {
			$mborres = 'IND';
		} else {
			die "mborres : $mborres";
		}
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'visitcpdt'}  = $visitCompdate;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'spDevId'}    = $spDevId;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'deviceType'} = $deviceType;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'tradeName'}  = $tradeName;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'visitdt'}    = $visitDate;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'mborres'}    = $mborres;
		$adslData{$subjid}->{'localPcrs'}->{$visitName}->{'spDevId'}    = $spDevId;
	}
}

sub subject_central_nbindings_by_visits {
	my ($subjid) = @_;
	for my $visit (sort keys %{$advaData{$subjid}->{'visits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $advaData{$subjid}->{'visits'}->{$visit}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'};
		# p$advaData{$subjid}->{'visits'}->{$visit};
		# die;
		my $avalc     = $advaData{$subjid}->{'visits'}->{$visit}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'} // die;
		my $visitcpdt = $advaData{$subjid}->{'visits'}->{$visit}->{'visitDate'}     // die;
		my $visitdt   = $advaData{$subjid}->{'visits'}->{$visit}->{'visitDatetime'} // die;
		if (exists $adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'} && ($adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'} ne $avalc)) {
			next unless $avalc eq 'POS'; # If several conflicting tests on the same date, we only sustain the last positive one.
		}
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'visitdt'}   = $visitdt;
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'}     = $avalc;
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'visitcpdt'} = $visitcpdt;
	}
}

sub subject_symptoms_by_visits {
	my ($subjid) = @_;
	for my $symptomDatetime (sort keys %{$symptoms{$subjid}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $compsympt = $symptomDate;
		$compsympt =~ s/\D//g;

		# Comment these lines to stick with the visit date.
		my ($formerSymptomDate, $onsetStartOffset);
		if (exists $faces{$subjid}->{$symptomDate}) {
			my $altStartDate = $faces{$subjid}->{$symptomDate}->{'symptomsDates'}->{'First Symptom Date'} // die;
			unless ($altStartDate eq $symptomDate) {
				if ($altStartDate =~ /^....-..-..$/) {
					my $compalt = $altStartDate;
					$compalt =~ s/\D//g;
					if ($compalt < $compsympt) {
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'total'}++;
						$formerSymptomDate = $symptomDate;
						$onsetStartOffset  = time::calculate_days_difference("$symptomDate 12:00:00", "$altStartDate 12:00:00");
						# $stats{'faceData'}->{'symptoms'}->{'correctedStart'}->{'offsets'}->{$onsetStartOffset}++;
						$symptomDate = $altStartDate;
					}
				} else {
					# $stats{'faceData'}->{'symptoms'}->{'invalidDate'}++;
				}
			} else {
				# $stats{'faceData'}->{'symptoms'}->{'sameDate'}++;
			}
		} else {
			# $stats{'faceData'}->{'symptoms'}->{'noVisitData'}++;
		}
		# $stats{'faceData'}->{'symptoms'}->{'totalRowsParsed'}++;
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		my $totalSymptoms   = 0;
		my $hasOfficialSymptoms = 0;
		my $endDatetime = $symptoms{$subjid}->{'symptomsReports'}->{$symptomDatetime}->{'endDatetime'};
		my $visitName = $symptoms{$subjid}->{'symptomsReports'}->{$symptomDatetime}->{'visitName'} // die;
		for my $symptomName (sort keys %{$symptoms{$subjid}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}}) {
			next unless $symptoms{$subjid}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}->{$symptomName} eq 'Y';
			my $symptomCategory = symptom_category_from_symptom($symptomName);
			$adslData{$subjid}->{'symptoms'}->{$visitName}->{'symptoms'}->{$symptomName}->{'symptomCategory'} = $symptomCategory;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'onsetStartOffset'}    = $onsetStartOffset;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'formerSymptomDate'}   = $formerSymptomDate;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'symptomCompdate'}     = $symptomCompdate;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'symptomDate'}         = $symptomDate;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'totalSymptoms'}       = $totalSymptoms;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'endDatetime'}         = $endDatetime;
		$adslData{$subjid}->{'symptoms'}->{$visitName}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
}

sub symptom_category_from_symptom {
	my $symptomName = shift;
	my $symptomCategory;
	if (
		$symptomName eq 'NEW OR INCREASED COUGH' ||
		$symptomName eq 'NEW OR INCREASED SORE THROAT' ||
		$symptomName eq 'CHILLS' ||
		$symptomName eq 'FEVER' ||
		$symptomName eq 'DIARRHEA' ||
		$symptomName eq 'NEW LOSS OF TASTE OR SMELL' ||
		$symptomName eq 'NEW OR INCREASED SHORTNESS OF BREATH' ||
		$symptomName eq 'NEW OR INCREASED MUSCLE PAIN' ||
		$symptomName eq 'VOMITING'
	) {
		$symptomCategory = 'OFFICIAL';
	} elsif (
		$symptomName eq 'NEW OR INCREASED NASAL CONGESTION' ||
		$symptomName eq 'HEADACHE' ||
		$symptomName eq 'FATIGUE' ||
		$symptomName eq 'RHINORRHOEA' ||
		$symptomName eq 'NAUSEA' ||
		$symptomName eq 'NEW OR INCREASED WHEEZING'
	) {
		$symptomCategory = 'SECONDARY';
	} else {
		die "symptomName : $symptomName";
	}
	return $symptomCategory;
}

p%stats;
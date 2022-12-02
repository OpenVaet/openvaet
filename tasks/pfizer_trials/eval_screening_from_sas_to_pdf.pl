#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $sdSuppDsFile      = 'public/doc/pfizer_trials/pfizer_suppds_patients.json';
my $pdfDataFile       = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';
my $sentinelFile      = 'public/doc/pfizer_trials/FDA-CBER-2021-5683-0023500 to -0023507_125742_S1_M5_c4591001-A-c4591001-phase-1-subjects-from-dmw.csv';
my $randomizationFile = 'public/doc/pfizer_trials/subjects_randomization_dates_merged.json';

my %demographic      = ();
my %sdSuppDs         = ();
my %sentinels        = ();
my %pdfData          = ();
my %subjectsToRepair = ();
my %randomization    = ();


load_randomization();
load_demographic_subjects();
load_s_d_suppds_subjects();
load_sentinel();
load_pdf_data();

my %allSubs          = ();
my %presents         = ();
my $phase1Total      = 0;
my %stats            = ();
for my $subjectId (sort{$a <=> $b} keys %sdSuppDs) {
	my $screeningOrder = $sdSuppDs{$subjectId}->{'screeningOrder'} // die;
	if (exists $demographic{$subjectId} || exists $sentinels{$subjectId}) {
		my $screeningDate = $demographic{$subjectId}->{'screeningDate'} // $sentinels{$subjectId};
		if ($demographic{$subjectId}->{'isPhase1'}) {
			my $isPhase1  = $demographic{$subjectId}->{'isPhase1'}      // die;
			if ($isPhase1) {
				$phase1Total++;
			}
			$presents{$screeningOrder}->{'isPhase1'}  = $isPhase1;
		}
		if (exists $demographic{$subjectId}) {
			$presents{$screeningOrder}->{'screeningDateOrigin'} = 'demographic';
			$stats{'screeningDate'}->{'ok'}->{'demographic'}++;
		} else {
			$presents{$screeningOrder}->{'screeningDateOrigin'} = 'sentinels';
			$stats{'screeningDate'}->{'ok'}->{'sentinels'}++;
		}
		$presents{$screeningOrder}->{'subjectId'}     = $subjectId;
		$presents{$screeningOrder}->{'screeningDate'} = $screeningDate;
		$stats{'screeningDate'}->{'ok'}->{'total'}++;
	} else {
		$stats{'screeningDate'}->{'missing'}++;
		if (exists $pdfData{'subjects'}->{$subjectId} || exists $randomization{$subjectId}) {
			# say "missing screening date but appearing in some pdfs : [$subjectId]";
			if (exists $pdfData{'subjects'}->{$subjectId}->{'files'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-c4591001-subject-list-for-12-25-immuno-analysis-27jan2021.pdf'}) {
					$subjectsToRepair{$subjectId} = $screeningOrder;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-c4591001-subject-list-for-12-25-immuno-analysis-27jan2021.pdf'}++;
			} elsif (exists $pdfData{'subjects'}->{$subjectId}->{'files'}->{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-discontinued-patients.pdf'}) {
					$subjectsToRepair{$subjectId} = $screeningOrder;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-discontinued-patients.pdf'}++;
			} elsif (exists $pdfData{'subjects'}->{$subjectId}->{'files'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive.pdf'}) {
					$subjectsToRepair{$subjectId} = $screeningOrder;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive.pdf'}++;
			} elsif (exists $pdfData{'subjects'}->{$subjectId}->{'files'}->{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients-sensitive.pdf'}) {
					$subjectsToRepair{$subjectId} = $screeningOrder;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients-sensitive.pdf'}++;
			} elsif (exists $pdfData{'subjects'}->{$subjectId}->{'files'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf'}) {
					$subjectsToRepair{$subjectId} = $screeningOrder;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
					$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf'}++;
			} else {
				for my $file (sort keys %{$pdfData{'subjects'}->{$subjectId}->{'files'}}) {
					if (
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-any-malignancy.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-cerebrovascular.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-chf.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-leukemia.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-metastatic-tumour.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-periph-vasc.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-rheumatic.pdf' ||
						$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-report-cci-lymphoma.pdf') {
						$subjectsToRepair{$subjectId} = $screeningOrder;
						$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'labMeasurments'}->{'total'}++;
						$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'labMeasurments'}->{$file}++;
						last;
					}
				}
				if (!exists $subjectsToRepair{$subjectId}) {
					for my $file (sort keys %{$pdfData{'subjects'}->{$subjectId}->{'files'}}) {
						if (
							$file eq 'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-randomization-sensitive.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-randomization-sensitive.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-fa-interim-discontinued-patients.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-excluded-patients.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-fa-interim-adverse-events.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-protocol-deviations.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-adverse-events.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-fa-interim-narrative-sensitive.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-fa-interim-protocol-deviations-sensitive.pdf' ||
							$file eq 'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf')
						{
							$subjectsToRepair{$subjectId} = $screeningOrder;
							$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{'total'}++;
							$stats{'screeningDate'}->{'repaired'}->{'fromPdfs'}->{$file}++;
						}
					}
				}
			}
			if (!exists $subjectsToRepair{$subjectId} && exists $randomization{$subjectId}) {
				$subjectsToRepair{$subjectId} = $screeningOrder;
				$stats{'screeningDate'}->{'repaired'}->{'fromAdvaRandomization'}++;
				say "subjectId : $subjectId";
			}
			# p$pdfData{'subjects'}->{$subjectId};
		} else {
			$stats{'screeningDate'}->{'doesntAppear'}++;
		}
	}
	$stats{'screeningDate'}->{'total'}++;
	$allSubs{$screeningOrder} = $subjectId;
}

my ($latestPresentSubjectId, $latestPresentOrder, $latestScreeningDate);
for my $screeningOrder (sort{$b <=> $a} keys %presents) {
	my $subjectId           = $presents{$screeningOrder}->{'subjectId'}     // die;
	my $screeningDate       = $presents{$screeningOrder}->{'screeningDate'} // die;
	if ($latestScreeningDate) {
		die "$latestScreeningDate < $screeningDate" if $latestScreeningDate < $screeningDate;
	}
	$latestScreeningDate    = $screeningDate;
	$latestPresentOrder     = $screeningOrder;
	$latestPresentSubjectId = $subjectId;
	last;
}
die unless $latestPresentSubjectId && $latestPresentOrder;
say "latestPresentSubjectId : $latestPresentSubjectId";
say "latestPresentOrder     : $latestPresentOrder";
say "latestScreeningDate    : $latestScreeningDate";
say "phase1Total            : $phase1Total";
say "subjectsToRepair       : " . keys %subjectsToRepair;
p%stats;
say "no incremental order has a screening date inferior to a previous entry.";

# Printing .csv summary.
open my $out, '>:utf8', "public/doc/pfizer_trials/s_d_suppds_subjects_and_screening_dates.csv";
say $out "Screening Order;Subject Id;Screening Date (if any);Phase 1;Has HIV;";
my %screeningDates = ();
for my $screeningOrder (sort{$a <=> $b} keys %allSubs) {
	my $subjectId        = $allSubs{$screeningOrder} // die;
	my $screeningDate    = $presents{$screeningOrder}->{'screeningDate'} // '';
	my $isPhase1         = $presents{$screeningOrder}->{'isPhase1'};
	my $hasHIV           = $presents{$screeningOrder}->{'hasHIV'};
	if (defined $isPhase1) {
		$latestScreeningDate = $screeningDate;
		if ($isPhase1    == 0) {
			$isPhase1    = 'No';
		} else {
			$isPhase1    = 'Yes';
		}
	} else {
		$isPhase1 = '';
	}
	if (defined $hasHIV) {
		if ($hasHIV == 0) {
			$hasHIV = 'No';
		} else {
			$hasHIV = 'Yes';
		}
	} else {
		$hasHIV = '';
	}
	if (exists $subjectsToRepair{$subjectId}) {
		die unless $latestScreeningDate;
		$screeningDate = $latestScreeningDate;
	}
	if ($screeningDate) {
		my $screeningDateOrigin = $presents{$screeningOrder}->{'screeningDateOrigin'} // 'Approximative last day estime';
		$screeningDates{$subjectId}->{'screeningDate'}       = $screeningDate;
		$screeningDates{$subjectId}->{'isPhase1'}            = $isPhase1;
		$screeningDates{$subjectId}->{'hasHIV'}              = $hasHIV;
		$screeningDates{$subjectId}->{'screeningDateOrigin'} = $screeningDateOrigin;
	}
	say $out "$screeningOrder;$subjectId;$screeningDate;$isPhase1;$hasHIV;";
}
close $out;
for my $subjectId (sort{$a <=> $b} keys %demographic) {
	unless (exists $screeningDates{$subjectId}) {
		$screeningDates{$subjectId}->{'screeningDate'} = $demographic{$subjectId}->{'screeningDate'};
		$screeningDates{$subjectId}->{'screeningDateOrigin'} = 'Demographics but no XPT';
	}
}

open my $out2, '>:utf8', 'public/doc/pfizer_trials/subjects_screening_dates.json';
print $out2 encode_json\%screeningDates;
close $out2;
say "screeningDates         : " . keys %screeningDates;
# p%screeningDates;


sub load_demographic_subjects {
	open my $in, '<:utf8', $demographicFile or die "Missing file [$demographicFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographic = %$json;
}

sub load_s_d_suppds_subjects {
	open my $in, '<:utf8', $sdSuppDsFile or die "Missing file [$sdSuppDsFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%sdSuppDs = %$json;
}

sub load_sentinel {
	open my $in, '<:utf8', $sentinelFile or die "Missing file [$sentinelFile]";
	while (<$in>) {
		chomp $_;
		my ($subjectId, $screeningDate) = split ';', $_;
		next if $subjectId eq 'SUBJECTNUMBERSTR';
		die unless $subjectId =~ /^\d\d\d\d\d\d\d\d$/;
		my ($d, $m, $y) = $screeningDate =~ /(.*)\/(.*)\/(.*)/;
		$screeningDate = "$y$m$d";
		$sentinels{$subjectId} = $screeningDate;
	}
	close $in;
}

sub load_pdf_data {
	open my $in, '<:utf8', $pdfDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfData = %$json;
}

sub load_randomization {
	open my $in, '<:utf8', $randomizationFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	say "[$randomizationFile] -> patients : " . keys %randomization;
}
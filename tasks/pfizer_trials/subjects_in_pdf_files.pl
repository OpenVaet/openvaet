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
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::stat;
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use Math::Round qw(nearest);

my %filesNotes  = ();

set_file_notes();

my $fileDetails = "stats/pfizer_json_data.json";

my %fileDetails = ();
load_file_details();

# Files such as https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-060122/125742_S1_M5_CRF_c4591001-1007-10071050.pdf&currentLanguage=en
# aren't properly parsed ATM.


sub load_file_details {
	open my $in, '<:utf8', $fileDetails or die $!;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	for my $fileData (@{%$json{'files'}}) {
		my $fileLocal = %$fileData{'fileLocal'} // die;
		my $fileMd5   = %$fileData{'fileMd5'}   // die;
		my $fileShort = %$fileData{'fileShort'} // die;
		$fileDetails{$fileMd5}->{'fileLocal'} = $fileLocal;
		$fileDetails{$fileMd5}->{'fileShort'} = $fileShort;
	}
}

my %containsSubjects = ();
my %subjects      = ();
for my $file (glob "public/pfizer_documents/pdf_to_html_files/*") {
	my ($fileMd5) = $file =~ /public\/pfizer_documents\/pdf_to_html_files\/(.*)/;
	die unless $fileMd5;
	die unless exists $fileDetails{$fileMd5};
	my $fileLocal = $fileDetails{$fileMd5}->{'fileLocal'} // die;
	# next unless $fileLocal =~ /CRFs-for-site-/ || $fileLocal =~ /_S1_M5_CRF_/; ####### DEBUG.
	# next unless $fileLocal =~ /_S1_M5_c4591001-A-report-cci-/;
	# # p$fileDetails{$fileMd5};
	say $file;
	my %pages     = ();
	my $totalPatientsInFile = 0;
	my $totalRows = 0;
	for my $htmlFile (glob "public/pfizer_documents/pdf_to_html_files/$fileMd5/*.html") {
		next unless $htmlFile =~ /page/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$pages{$pageNum} = 1;
	}
	for my $pageNum (sort{$a <=> $b} keys %pages) {
		my $htmlFile = "public/pfizer_documents/pdf_to_html_files/$fileMd5/page$pageNum.html";
		# say "htmlFile : $htmlFile";
		my $content;
		open my $in, '<:utf8', $htmlFile;
		while (<$in>) {
			$content .= $_;
		}
		close $in;
		die unless $content;
		my $tree = HTML::Tree->new();
		$tree->parse($content);
		my $body = $tree->find('body');
		my @divs = $body->find('div');

		# We first extract all the patient ids in the page, so we known how many to expect.
		if (
			$fileLocal =~ /125742_S1_M5_c4591001-A-c4591001-phase-1-subjects-from-dmw\.pdf/ ||
			$fileLocal =~ /125742_S1_M5_c4591001-A-first-c4591001-360-participants-enrolled-v1-13aug20-update\.pdf/ ||
			$fileLocal =~ /125742_S1_M5_c4591001-A-201114-hiv-preferred-terms\.pdf/ ||
			$fileLocal =~ /_S1_M5_c4591001-A-report-cci-/
		) {
			my %subjectIds = parse_isolated_subject_ids(@divs);
			for my $topMargin (sort{$a <=> $b} keys %subjectIds) {
				$totalRows++;
				my $subjectId = $subjectIds{$topMargin}->{'subjectId'} // die;
				unless (exists $subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}) {
					$totalPatientsInFile++;				
				}
				$subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}->{'totalRows'}++;
				$subjects{'files'}->{$fileLocal}->{'subjects'}->{$subjectId} = 1;
			}
		} elsif ($fileLocal =~ /CRFs-for-site-/ || $fileLocal =~ /_S1_M5_CRF_/) {
			my %subjectIds = parse_crf_subject_ids(@divs);
			for my $topMargin (sort{$a <=> $b} keys %subjectIds) {
				$totalRows++;
				my $subjectId = $subjectIds{$topMargin}->{'subjectId'} // die;
				unless (exists $subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}) {
					$totalPatientsInFile++;				
				}
				$subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}->{'totalRows'}++;
				$subjects{'files'}->{$fileLocal}->{'subjects'}->{$subjectId} = 1;
			}
		} else {
			my %subjectIds = parse_unique_subject_ids(@divs);
			for my $topMargin (sort{$a <=> $b} keys %subjectIds) {
				$totalRows++;
				my $uSubjectId = $subjectIds{$topMargin}->{'uSubjectId'} // die;
				my ($subjectId) = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
				$subjects{'subjects'}->{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
				$subjects{'subjects'}->{$subjectId}->{'uSubjectId'} = $uSubjectId;
				unless (exists $subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}) {
					$totalPatientsInFile++;				
				}
				$subjects{'subjects'}->{$subjectId}->{'files'}->{$fileLocal}->{'totalRows'}++;
				$subjects{'files'}->{$fileLocal}->{'subjects'}->{$subjectId} = 1;
			}
		}
	}
	$subjects{'files'}->{$fileLocal}->{'totalRows'} = $totalRows;
	$subjects{'files'}->{$fileLocal}->{'totalSubjects'} = $totalPatientsInFile;
	say "totalRows           : $totalRows";
	say "totalPatientsInFile : $totalPatientsInFile";
	say "totalSubjects       : " . keys %{$subjects{'subjects'}};
	if ($totalPatientsInFile) {
		$containsSubjects{$fileLocal} = 1;
	}
	# die;
}

sub parse_isolated_subject_ids {
	my @divs = @_;
	my %subjectIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if ($word =~ /^\d\d\d\d\d\d\d\d$/ && $word !~ /^9000\d\d\d\d$/) {
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				die unless looks_like_number $word;
				$entryNum++;
				$subjectIds{$topMargin}->{'entryNum'}  = $entryNum;
				$subjectIds{$topMargin}->{'subjectId'} = $word;
			}
		}
	}
	return %subjectIds;
}

sub parse_crf_subject_ids {
	my @divs = @_;
	my %subjectIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($lastWord, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if ($word =~ /^\d\d\d\d\d\d\d\d/ && $lastWord eq 'No:') {
				die unless $word =~ /^\d\d\d\d\d\d\d\d$/;
				$lastWord = undef;
				my $style = $div->attr_get_i('style');
				($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$entryNum++;
				$subjectIds{$topMargin}->{'entryNum'}  = $entryNum;
				$subjectIds{$topMargin}->{'subjectId'} = $word;
			}
			$lastWord = $word;
		}
	}
	return %subjectIds;
}

sub parse_unique_subject_ids {
	my @divs = @_;
	my %subjectIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialData, $siteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if (($word =~ /C4591001/ || $word =~ /^\d\d\d\d$/ || $word =~ /^\d\d\d\d\d\d\d\d/)) {
				if ($word =~ /C4591001/) {
					unless ($word =~ /^C\d\d\d\d\d\d\d$/) {
						($word) = 'C4591001';
					}
					my $style = $div->attr_get_i('style');
					($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					$trialData = $word;
					$siteData  = undef;
					$init++;
				} elsif ($word =~ /^\d\d\d\d$/) {
					unless ($trialData && !$siteData) {
						$trialData = undef;
						$siteData  = undef;
						$topMargin = undef;
						next;
					}
					$siteData = $word;
				} else {
					if ($trialData && $siteData) {
						my $uSubjectId = "$trialData $siteData $word";
						$uSubjectId =~ s/\^//;
						unless (length $uSubjectId == 22) {
							$uSubjectId =~ s/†//;
							unless (length $uSubjectId == 22) {
								$uSubjectId =~ s/∞//;
								unless (length $uSubjectId == 22) {
									$uSubjectId =~ s/#//;
									unless (length $uSubjectId == 22) {
										$uSubjectId =~ s/\*//;
										unless (length $uSubjectId == 22) {
											$uSubjectId =~ s/,//;
											unless (length $uSubjectId == 22) {
												$uSubjectId =~ s/\'//;
												unless (length $uSubjectId == 22) {
													$uSubjectId =~ s/\)\.//;
													$uSubjectId =~ s/\)//;
													unless (length $uSubjectId == 22) {
														unless (length $uSubjectId == 22) {
															$uSubjectId =~ s/\]//;
															unless (length $uSubjectId == 22) {
																$uSubjectId =~ s/://;
																unless (length $uSubjectId == 22) {
																	$uSubjectId =~ s/;//;
																	unless (length $uSubjectId == 22) {
																		($uSubjectId) = split ' \(', $uSubjectId;
																		next if length $uSubjectId > 36;
																		die "uSubjectId : [$uSubjectId]" unless (length $uSubjectId == 22);
																	}
																}
															}
														}
													}
												}
											}
										}
									}
								}
							}
						}
						$entryNum++;
						$subjectIds{$topMargin}->{'entryNum'}            = $entryNum;
						$subjectIds{$topMargin}->{'uSubjectId'}          = $uSubjectId;
						$subjectIds{$topMargin}->{'uSubjectIdTopMargin'} = $topMargin;
						$trialData = undef;
						$siteData  = undef;
						$topMargin = undef;
					}
				}
			}
		}
	}
	return %subjectIds;
}

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_pdf_data_patients.json";
print $out encode_json\%subjects;
close $out;

# Prints PDF files summary.
open my $out2, '>:utf8', "$outputFolder/pfizer_pdf_files_subjects.csv";
say $out2 "File;Total Rows;Total Subjects;Notes;";
for my $file (sort keys %{$subjects{'files'}}) {
	my $totalRows = $subjects{'files'}->{$file}->{'totalRows'} // die;
	my $totalSubjects = $subjects{'files'}->{$file}->{'totalSubjects'} // die;
	my $notes = '';
	if (exists $filesNotes{$file}) {
		$notes = $filesNotes{$file} // die;
	}
	say $out2 "$file;$totalRows;$totalSubjects;$notes;";
}
close $out2;

# Console display of files containing subjects.
for my $file (sort keys %containsSubjects) {
	my $filePrint = $file;
	my $localUrl = "http://127.0.0.1:3000/pfizearch/viewer?pdf=$filePrint&currentLanguage=en";
	say "[$filePrint] - [$localUrl]";
}

sub set_file_notes {
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_356h.pdf'}                            = 'Application to market form';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_3674.pdf'}                            = 'Certificate of compliace';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_cover.pdf'}                           = 'Letter from Elisa Harkins to Marion Gruber';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_debarment.pdf'}                       = 'Debarment certification';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_exclusivity-claim.pdf'}               = 'Exclusivity claim';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_fast-track-designation.pdf'}          = 'Document related to the "fast track" procedure';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_financial-cert-3454.pdf'}             = 'Investigators by sites listing';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_financial-cert-bias.pdf'}             = 'Steps taken to minimize bias';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_ipsp-agreed-letter.pdf'}              = 'Letter from Doran Fink -S to Aghajani Memar (pediatric study plan agreement)';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_priority-review-request.pdf'}         = 'Adverse effects statistics';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_trans-of-oblig.pdf'}                  = 'TRANSFER OF OBLIGATIONS from BionTech to Pfizer';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_us-agent-authorization.pdf'}          = 'Letter (appointment of agents)';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_userfee.pdf'} = '2 Billions userfee coversheet';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M1_waiver-req-designated-suffix.pdf'} = 'WAIVER REQUEST FOR FDA-DESIGNATED SUFFIX FOR BIOLOGICS - March 2020';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_22_introduction.pdf'} = 'Introduction for BLA';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_24_nonclinical-overview.pdf'} = 'Non Clinical Overview of BNT162b2';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_26_pharmkin-tabulated-summary.pdf'} = 'Pharmacokinetics details';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_26_pharmkin-written-summary.pdf'} = 'Pharmacokinetics written summary';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_27_literature-references.pdf'} = 'Literature References';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M2_27_synopses-indiv-studies.pdf'} = 'Synopses of individual studies';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M4_4223_185350.pdf'} = 'A Tissue Distribution Study of a [3 H]-Labelled Lipid Nanoparticle-mRNA Formulation Containing ALC-0315 and ALC-0159 Following Intramuscular Administration in Wistar Han Rats';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M4_4223_R-20-0072.pdf'} = 'EXPRESSION OF LUCIFERASE-ENCODING MODRNA AFTER I.M. APPLICATION OF GMP-READY ACUITAS LIPID NANOPARTICLE FORMULATION';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-ad-hoc-label-tables.pdf'} = 'Adverse effects statistics';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-errata.pdf'} = 'Empty Errata File';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-oversight-committees.pdf'} = 'Monitoring committee interim report';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-protocol.pdf'} = 'Interim protocol';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-interim-mth6-oversight-committees.pdf'} = 'Monitoring committee month 6 report';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-interim-mth6-protocol.pdf'} = 'Month 6 protocol';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-bmi-12-15-scale.pdf'} = 'Births during the study statistics';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-A-comorbidity-categories.pdf'} = 'Commorbidities files inventory';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-T-S-final-reacto-tables-track.pdf'} = 'Adverse effects statistics';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-T-S-roadmap.pdf'} = 'Roadmap reactogenicity dataset';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-T-S-summary-differences-csr-vs-update.pdf'} = 'Summary of Differences Between CSR Reactogenicity Data and Updated Reactogenicity Data';
	$filesNotes{'pfizer_documents/native_files/pd-production-030122/125742_S1_M5_c4591001-T-S-suppl-arg.pdf'} = 'Supplemental Analysis Reviewer Guide';
	$filesNotes{'pfizer_documents/native_files/pd-production-032422/125742_S1_M1_priority-review-request.pdf'} = 'REQUEST FOR PRIORITY REVIEW';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-audit-certificates.pdf'} = 'Audit Certificate';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-iec-irb-consent-form.pdf'} = ' LIST OF INDEPENDENT ETHICS COMMITTE & Misc administrative documents';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-invest-signature.pdf'} = 'Final Analysis Interim Report';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-publications.pdf'} = 'Publications based on the study on November 24, 2020';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-sample-crf.pdf'} = 'Sample CRF Report';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-sponsor-signature.pdf'} = 'CLINICAL STUDY REPORT APPROVAL FORM';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-interim-mth6-audit-certificates.pdf'} = 'Audit Certificate';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-interim-mth6-invest-signature.pdf'} = 'Administrative certification';
	$filesNotes{'pfizer_documents/native_files/pd-production-040122/reissue_5.3.6 postmarketing experience.pdf'} = 'CUMULATIVE ANALYSIS OF POST-AUTHORIZATION ADVERSE EVENT REPORTS OF PF-07302048 (BNT162B2) RECEIVED THROUGH 28-FEB-2021';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-adverse-events.pdf'} = 'Adverse effects details by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-compliance.pdf'} = 'Various data by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-demographics.pdf'} = 'Various data by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-discontinued-patients.pdf'} = 'Various data by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-excluded-patients.pdf'} = 'Various data by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-iec-irb.pdf'} = 'List of independent ethics committees';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-invest-signature.pdf'} = 'Clinical trial report sign-off sheet';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-investigators.pdf'} = 'List of Investigators';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-lab-measurements.pdf'} = 'Various data by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-notes-for-reader.pdf'} = 'Participant data listings - Notes for the reader';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-patient-batches.pdf'} = 'Products tracking table';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-protocol-deviations.pdf'} = 'Exclusions by randomization number';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-protocol.pdf'} = 'CLINICAL TRIAL PROTOCOL INCLUDING AMENDMENTS NOS. 01 TO 06';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-report-body.pdf'} = 'INTERIM CLINICAL STUDY REPORT - BNT162-01';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-sample-crf.pdf'} = 'Visit 0 (Screening) form';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-sap.pdf'} = 'Statistical Analysis Plan';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-sponsor-personnel-list.pdf'} = 'List of sponsor personnel who materially affected the trial conduct';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-sponsor-signature.pdf'} = 'Clinical Trial Report - Sign-off Sheet';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01-interim3-synopsis.pdf'} = 'Interim Clinical Study Report';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01_10010.pdf'} = 'CRS Mannheim discontinued';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01_10075.pdf'} = 'CRS Mannheim allocated';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01_20116.pdf'} = 'CRS Berlin discontinued';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01_20215.pdf'} = 'CRS Berlin allocated';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_bnt162-01_20242.pdf'} = 'CRS Berlin allocated';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-sample-crf.pdf'} = 'Annotated Study Book for Study Design: C4591001';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-sponsor-signature.pdf'} = 'Clinical study report approval form';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_bnt162-01-S-acrf.pdf'} = 'Demographics form';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_bnt162-01-S-csdrg.pdf'} = 'Clinical Study Data Reviewer\'s Guide';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_c4591001-S-Supp-acrf.pdf'} = 'Annotated Study Book for Study Design: C4591001';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_c4591001-S-acrf.pdf'} = 'Annotated Study Book for Study Design: C4591001';
	$filesNotes{'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_bnt162-01-A-adrg.pdf'} = 'Analysis Data Reviewer Guide';
	$filesNotes{'pfizer_documents/native_files/pd-production-060122/125742_S1_M2_summary-biopharm.pdf'} = 'SUMMARY OF BIOPHARMACEUTIC STUDIES AND ASSOCIATED ANALYTICAL METHODS';
	$filesNotes{'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5314_shi-sop-10011.pdf'} = 'Manual 96-well Neutralization Assay for the Detection of Functional Antibodies';
	$filesNotes{'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-fa-interim-patient-batches.pdf'} = 'Batches by trial sites';
	$filesNotes{'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-interim-mth6-patient-batches.pdf'} = 'Batches by trial sites';
	$filesNotes{'pfizer_documents/native_files/pd-production-060122/125742_S1_M5_5351_c4591001-interim-mth6-publications.pdf'} = 'Publications based on the study on March 17, 2021';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-interlab-standard.pdf'} = 'List of Laboratories - Interim - 6 Month Update';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-011321-vials.pdf'} = 'Letter from Stevanato Group to the DMF';
	$filesNotes{'pfizer_documents/native_files/pd-production-111721/5.2-listing-of-clinical-sites-and-cvs-pages-1-41.pdf'} = 'List of all clinical sites';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-sap.pdf'} = 'Statistical Analysis Plan';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_com195lkz-carton-kzoo.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_com195lpus-carton-puurs.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_com25ctkz-carton-kzoo.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_hospira-diluent-label.pdf'} = 'Diluent For Use with [COVID-19 mRNA Vaccine (nucleoside modified)] COMIRNATYT';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-011793-vials.pdf'} = 'Letter of authorization';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-10953-stopper.pdf'} = 'Letter of authorization';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_right-of-reference.pdf'} = 'STATEMENT OF RIGHT TO REFERENCE';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M5_5354_wi235284-protocol.pdf'} = 'RSV in Older Adults and Pregnant Women Study';
	$filesNotes{'pfizer_documents/native_files/pd-production-080122/125742_S2_M5_54_ezeanolue-e-2019.pdf'} = 'Best practices for immunization';
	$filesNotes{'pfizer_documents/native_files/pd-production-110122/125742_S1_M4_20256434.pdf'} = 'A Combined Fertility and Developmental Study (Including Teratogenicity and Postnatal Investigations) of BNT162b1, BNT162b2 and BNT162b3 by Intramuscular Administration in the Wistar Rat';
	$filesNotes{'pfizer_documents/native_files/pd-production-111721/5.2-tabular-listing.pdf'} = 'List of clinical studies included in the biologics licence application';
	$filesNotes{'pfizer_documents/native_files/pd-production-111721/5.3.6-postmarketing-experience.pdf'} = 'CUMULATIVE ANALYSIS OF POST-AUTHORIZATION ADVERSE EVENT REPORTS';
	$filesNotes{'pfizer_documents/native_files/pd-production-120121/Pages-42-289-Section-5.2-listing-clinical-sites-cvs_Part-A.pdf'} = 'Abbreviated CV Template';
	$filesNotes{'pfizer_documents/native_files/pd-production-120121/Pages-42-289-Section-5.2-listing-clinical-sites-cvs_Part-B.pdf'} = 'Abbreviated CV Template';
	$filesNotes{'pfizer_documents/native_files/pd-production-121321/STN-125742_0_0-Section-2.7.3-Summary-of-Clinical-Efficacy.pdf'} = 'SUMMARY OF CLINICAL EFFICACY';
	$filesNotes{'pfizer_documents/native_files/pd-production-121321/signed-F21-5683-CBER-Dec-13-2021-Response-Letter.pdf'} = 'DHHS Letter to Aaaron Siri';
	$filesNotes{'pfizer_documents/native_files/pd-production-122221/Supplemental-Index-12-22-21.pdf'} = 'Exclude Inspection Related';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-fa-interim-sap.pdf'} = 'Protocol C4591001';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-011820-vials.pdf'} = 'Letter of authorization';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-012683-vials.pdf'} = 'Letter of authorization';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_loa-dmf-031786-vials.pdf'} = 'Letter of authorization';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_comvlabp-vial-puurs.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_fk-diluent-carton.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_fk-diluent-stamp.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_hospira-diluent-carton.pdf'} = 'Comirnaty Carton Picture';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_com25ctpus-carton-puurs.pdf'} = 'Comirnaty Carton Label';
	$filesNotes{'pfizer_documents/native_files/pd-production-070122/125742_S2_M1_comvlabkz-vial-kzoo.pdf'} = 'Comirnaty Carton Label';
}
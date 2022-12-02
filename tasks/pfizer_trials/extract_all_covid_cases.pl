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

# Original cases files of the patients is here,page 1 to 65, finalized on November 24, 2020, "Listing of Subjects With Postvaccination SARS-CoV-2 NAAT-Positive Nasal Swab and COVID-19 Signs and Symptoms – Dose 1 All-Available Efficacy Population"
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf&currentLanguage=en

# Another file of interest is https://openvaet.org/pfizearch/pdf_search_details?fileShort=pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf&fileMd5=853a60a8850b3d52571c55de8d863225&terms=shortness%20of%20breath&allTermsOnly=true&currentLanguage=fr
# 16.2.8.1.IA1 Listing of Subjects With Postvaccination SARS-CoV-2 NAAT-Positive Nasal Swab and COVID-19 Signs and Symptoms – Dose 1 All-Available Efficacy Population – Interim Analysis 1
# Finalized on December 2, 2020, page 1 to 38.

# Another file, page 1 to 225, finalized on April 1, 2021, "Listing of Subjects With First COVID-19 Occurrence After Dose 1 – Blinded Placebo-Controlled Follow-up Period – Dose 1 All-Available Efficacy Population"
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf&currentLanguage=en
# There seems to be the exact same file on https://openvaet.org/pfizearch/pdf_search_details?fileShort=pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-lab-measurements-sensitive.pdf&fileMd5=31a4337f663a96dfc5db9df2b5d480c8&terms=shortness%20of%20breath&allTermsOnly=true&currentLanguage=fr

# This script parses these files, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $casesPdfFile   = "public/pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $casesPdfFile;
my $casesPdfFolder = "raw_data/pfizer_trials/cases";
my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $casesPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$casesPdfFile\" \"$casesPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 22 to 4376 (table "All Subjects").
my %patients = ();
my $totalPatients = 0;
extract_all_subjects_table();
# p%patients;
say "totalPatients   : $totalPatients";

# # Generates weekly stats, prints .CSV.
# my %stats = ();
# my $patientsToSept6 = 0;
# open my $out, '>:utf8', "$outputFolder/pfizer_trial_cases.csv";
# say $out "number;patient id;sex;age (years);screening date;week number;";
# for my $uSubjectId (sort keys %patients) {
# 	my $casesMonth      = $patients{$uSubjectId}->{'casesMonth'}      // die;
# 	my $casesDate       = $patients{$uSubjectId}->{'casesDate'}       // die;
# 	my $casesWeekNumber = $patients{$uSubjectId}->{'casesWeekNumber'} // die;
# 	$stats{$casesWeekNumber}->{'cases'}++;
# 	$stats{$casesWeekNumber}->{'month'} = $casesMonth if !exists $stats{$casesWeekNumber}->{'month'};
# 	if ($casesDate >= '20200720' && $casesDate <= '20200906') {
# 		$patientsToSept6++;
# 	}
# }
# close $out;
# say "patientsToSept6 : $patientsToSept6";

# # Prints weekly stats.
# open my $out2, '>:utf8', "$outputFolder/cases_weekly_recruitment.csv";
# say $out2 "month;week number;cases;";
# for my $weekNumber (sort{$a <=> $b} keys %stats) {
# 	my $cases = $stats{$weekNumber}->{'cases'} // die;
# 	my $month = $stats{$weekNumber}->{'month'} // die;
# 	say $out2 "$month;$weekNumber;$cases;";
# }
# close $out2;

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_cases_1.json";
print $out3 encode_json\%patients;
close $out3;

sub verify_pdf_structure {
	for my $htmlFile (glob "$casesPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 217) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$casesPdfFolder/page$pageNum.html";
		say "htmlFile : $htmlFile";
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

		open my $out, '>:utf8', 'tmp.html';
		print $out $content;
		close $out;

		# We first extract all the patient ids in the page, so we known how many to expect.
		my %patientsIds        = parse_patients_ids(@divs);
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;
		p%patientsIds;

		# # We then look for cases dates.
		# my %casesDates = parse_cases_dates($pageTotalPatients, @divs);

		# # We then look for the cases groups.
		# my %casesData  = parse_cases_groups($pageNum, $pageTotalPatients, @divs);
		# # p%patientsIds;
		# # p%casesDates;
		# # p%casesData;

		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $uSubjectId              = $patientsIds{$topMargin}->{'uSubjectId'}                     // die;
			my ($subjectId) = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
			die unless $subjectId;
			my $entryNum               = $patientsIds{$topMargin}->{'entryNum'}                      // die;
		# 	my $casesDate       = $casesDates{$topMargin}->{'casesDate'}       // die;
		# 	my $casesMonth      = $casesDates{$topMargin}->{'casesMonth'}      // die;
		# 	my $casesWeekNumber = $casesDates{$topMargin}->{'casesWeekNumber'} // die;
		# 	my $casesYear       = $casesDates{$topMargin}->{'casesYear'}       // die;
		# 	my $casesGroup      = $casesData{$topMargin}->{'casesGroup'};
		# 	# p$casesData{$topMargin};
			$patients{$subjectId}->{'uSubjectId'}  = $uSubjectId;
			$patients{$subjectId}->{'pageNum'}  = $pageNum;
			$patients{$subjectId}->{'entryNum'} = $entryNum;
		# 	$patients{$uSubjectId}->{'casesDate'}       = $casesDate;
		# 	$patients{$uSubjectId}->{'casesMonth'}      = $casesMonth;
		# 	$patients{$uSubjectId}->{'casesWeekNumber'} = $casesWeekNumber;
		# 	$patients{$uSubjectId}->{'casesYear'}       = $casesYear;
		# 	$patients{$uSubjectId}->{'casesGroup'}      = $casesGroup;
		# 	for my $doseNum (sort{$a <=> $b} keys %{$casesData{$topMargin}->{'doses'}}) {
		# 		my $dose       = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'dose'}       // next;
		# 		my $month      = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'month'}      // next;
		# 		my $dosage     = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'dosage'};
		# 		my $doseDate   = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'doseDate'};
		# 		my $weekNumber = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'weekNumber'} // die;
		# 		my $year       = $casesData{$topMargin}->{'doses'}->{$doseNum}->{'year'}       // die;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'dose'}       = $dose;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'month'}      = $month;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'dosage'}     = $dosage;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'doseDate'}   = $doseDate;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'weekNumber'} = $weekNumber;
		# 		$patients{$uSubjectId}->{'doses'}->{$doseNum}->{'year'}       = $year;
		# 	}
		}
		# last if $pageNum == 65;
		last if $pageNum == 216;
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialAndSiteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | $text";
		if (($text =~ /C4591001/ || $text =~ /\d\d\d\d\d\d\d\d/)) {
			if ($text =~ /C4591001/) {
				# say "text : $text";
				unless ($text =~ /^C\d\d\d\d\d\d\d \d\d\d\d$/) {
					($text) = $text =~ /(C\d\d\d\d\d\d\d \d\d\d\d)/;
					die unless $text;
				}
				my $style = $div->attr_get_i('style');
				($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$trialAndSiteData = $text;
				$init++;
				# say "trialAndSiteData : $trialAndSiteData";
			} else {
				# say "text : $text";
				if ($trialAndSiteData) {
					my $uSubjectId = "$trialAndSiteData $text";
					$uSubjectId =~ s/\^//;
					unless (length $uSubjectId == 22) {
						$uSubjectId =~ s/†//;
						unless (length $uSubjectId == 22) {
							($uSubjectId) = split ' \(', $uSubjectId;
							# say "uSubjectId : [$uSubjectId]";
							die "uSubjectId : [$uSubjectId]" unless (length $uSubjectId == 22);
						}
					}
					# die;
					$entryNum++;
					$patientsIds{$topMargin}->{'entryNum'}               = $entryNum;
					$patientsIds{$topMargin}->{'uSubjectId'}          = $uSubjectId;
					$patientsIds{$topMargin}->{'uSubjectIdTopMargin'} = $topMargin;
					# say "$entryNum | $uSubjectId";
					$trialAndSiteData = undef;
					$topMargin = undef;
				}
			}
		}
	}
	# p%patientsIds;
	unless ($init == keys %patientsIds) {
		p%patientsIds;
		die "$init != " . keys %patientsIds;
	}
	return %patientsIds;
}

sub parse_cases_dates {
	my ($pageTotalPatients, @divs) = @_;
	my %casesDates = ();
	my ($dNum, $entryNum) = (0, 0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | $text";
		if ((
				(
					$text =~ /^.....2020$/ ||
					(
						$text =~ /^..-.. .....2020$/ ||
						$text =~ />.. .....2020$/
					) ||
					(
						$text =~ /^^..-.. .....2020 \d\d\d\d\d\d/ ||
						$text =~ />.. .....2020 \d\d\d\d\d\d/
					)
				) ||
				(
					$text =~ /^.....2021$/ ||
					(
						$text =~ /^..-.. .....2021$/ ||
						$text =~ />.. .....2021$/
					) ||
					(
						$text =~ /^^..-.. .....2021 \d\d\d\d\d\d/ ||
						$text =~ />.. .....2021 \d\d\d\d\d\d/
					)
				)
			) && $text !~ /Page/) {
			# say "$dNum | $text";
			my ($date) = $text =~ /(.....2020)/;
			unless ($date) {
				($date) = $text =~ /(.....2021)/;
			}
			die unless $date;
			my ($casesDate, $casesYear, $casesMonth, $casesWeekNumber) = convert_date($date);
			$entryNum++;
			my $style = $div->attr_get_i('style');
			my ($topMargin) = $style =~ /top:(.*)px;/;
			die unless looks_like_number $topMargin;
			$casesDates{$topMargin}->{'casesDateTopMargin'} = $topMargin;
			$casesDates{$topMargin}->{'casesDate'}          = $casesDate;
			$casesDates{$topMargin}->{'casesYear'}          = $casesYear;
			$casesDates{$topMargin}->{'casesMonth'}         = $casesMonth;
			$casesDates{$topMargin}->{'casesWeekNumber'}    = $casesWeekNumber;
			# say "$dNum | $casesDate";
		}
	}
	# p%casesDates;
	unless ($entryNum == $pageTotalPatients) {
		die "$entryNum != $pageTotalPatients";
	}
	return %casesDates;
}

sub convert_date {
	my $dt = shift;
	my ($d, $m, $y) = $dt =~ /(..)(...)(....)/;
	$m = convert_month($m);
	my $weekNumber = iso_week_number("$y-$m-$d");
	(undef, $weekNumber) = split '-', $weekNumber;
	$weekNumber =~ s/W//;
	return ("$y$m$d", $y, $m, $weekNumber);
}

sub convert_month {
	my $m = shift;
	return '01' if $m eq 'JAN';
	return '02' if $m eq 'FEB';
	return '03' if $m eq 'MAR';
	return '04' if $m eq 'APR';
	return '05' if $m eq 'MAY';
	return '06' if $m eq 'JUN';
	return '07' if $m eq 'JUL';
	return '08' if $m eq 'AUG';
	return '09' if $m eq 'SEP';
	return '10' if $m eq 'OCT';
	return '11' if $m eq 'NOV';
	return '12' if $m eq 'DEC';
	die "failed to convert month [$m]";
}

sub parse_cases_groups {
	my ($pageNum, $pageTotalPatients, @divs) = @_;
	my %casesData = ();
	my ($dNum, $entryNum, $firstAttempt) = (0, 0, 1);
	my $casesGroupStart = 0;
	my $casesGroupDone  = 0;
	my ($formerLine, $formerTopMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		my $style = $div->attr_get_i('style');
		my ($topMargin) = $style =~ /top:(.*)px;/;
		die unless looks_like_number $topMargin;
		# say "$dNum | [$text]" if !$formerLine;
		# say "$dNum | [$text] -> $formerLine" if $formerLine;
		if ($text =~ /\// && $casesGroupStart == 1) {
			$casesGroupDone = 1;
		}
		process_div:
		if ($casesGroupDone == 0) {
			if (
					$text eq 'Pla cebo' || $text eq 'Placebo' || (
					($text =~ /^\(.. \μg\)$/ && $formerLine eq 'BNT162b1')
				)
			) {
				$entryNum++;
				# say "$dNum | $text";
				$casesGroupStart = 1;
				if ($text =~ /^\(.. μg\)$/) {
					$casesData{$formerTopMargin}->{'casesGroup'}     = "BNT162b2 $text";
					$casesData{$formerTopMargin}->{'casesTopMargin'} = $formerTopMargin;
				} else {
					$casesData{$topMargin}->{'casesGroup'}     = "Placebo";
					$casesData{$topMargin}->{'casesTopMargin'} = $topMargin;
				}
			} elsif (
					$text eq 'Pla cebo' || $text eq 'Placebo' || (
					($text =~ /^\(.. \μg\)$/ && $formerLine eq 'BNT162b2')
				)
			) {
				$entryNum++;
				# say "$dNum | $text";
				$casesGroupStart = 1;
				if ($text =~ /^\(.. μg\)$/) {
					$casesData{$formerTopMargin}->{'casesGroup'}     = "BNT162b2 $text";
					$casesData{$formerTopMargin}->{'casesTopMargin'} = $formerTopMargin;
				} else {
					$casesData{$topMargin}->{'casesGroup'}     = "Placebo";
					$casesData{$topMargin}->{'casesTopMargin'} = $topMargin;
				}
			}
			$formerLine = $text;
			$formerTopMargin = $topMargin;
		} else {
			if ($casesGroupDone == 1) {
				# say "$dNum | [$text]";
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				if ($text =~ /....2020\/ .....2020/ || $text =~ /....2020\/ .....2021/ || $text =~ /....2021\/ .....2021/) {
					my @dates = split '\/ ', $text;
					for my $date (@dates) {
						$date =~ s/\///;
						my ($doseDate, $year, $month, $weekNumber) = convert_date($date);
						$casesData{$topMargin}->{'doseNumDate'}++;
						my $doseNumDate = $casesData{$topMargin}->{'doseNumDate'} // die;
						$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'doseDate'}   = $doseDate;
						$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'year'}       = $year;
						$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'month'}      = $month;
						$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'weekNumber'} = $weekNumber;
						# say "date : [$date] -> $doseDate, $year, $month, $weekNumber";
					}
					$formerLine = $text;
					$formerTopMargin = $topMargin;
				} elsif ($text =~ /^BNT162b\d BNT162b\d$/) {
					my @doses = split ' ', $text;
					for my $dose (@doses) {
						$casesData{$formerTopMargin}->{'doseNum'}++;
						my $doseNum = $casesData{$formerTopMargin}->{'doseNum'} // die;
						$casesData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $dose;
						# say "doses : $doseNum - $dose";
					}
				} elsif ($text =~ /^BNT162b\d/) {
					$casesData{$formerTopMargin}->{'doseNum'}++;
					my $doseNum = $casesData{$formerTopMargin}->{'doseNum'} // die;
					$casesData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $text;
				} elsif ($text =~ /^\(.. μg\)$/ || $text =~ /^\(... μg\)$/) {
					$casesData{$formerTopMargin}->{'dosageNum'}++;
					my $dosageNum = $casesData{$formerTopMargin}->{'dosageNum'} // die;
					$casesData{$formerTopMargin}->{'doses'}->{$dosageNum}->{'dosage'} = $text;
					# p$casesData{$formerTopMargin}->{'doses'};
					# say "$formerLine - $dosageNum - $text";
					# die;
				} elsif ($text =~ /^\(... μg\) \(.. μg\)$/ || $text =~ /^\(.. μg\) \(.. μg\)$/) {
					my @dosages = split '\) \(', $text;
					# say "$dNum | [$text]";
					# p@dosages;
					for my $dosage (@dosages) {
						if ($dosage =~ /\)/) {
							$dosage = "($dosage";
						} else {
							$dosage = "$dosage)";
						}
						$casesData{$formerTopMargin}->{'dosageNum'}++;
						my $dosageNum = $casesData{$formerTopMargin}->{'dosageNum'} // die;
						$casesData{$formerTopMargin}->{'doses'}->{$dosageNum}->{'dosage'} = $dosage;
						# say "dosage : $dosage";
					}
					# p$casesData{$formerTopMargin}->{'doses'};
					# say "$formerLine - $dosageNum - $text";
					# die;
				} elsif ($text =~ /Placebo /) {
					my @doses = split ' ', $text;
					for my $dose (@doses) {
						$casesData{$formerTopMargin}->{'doseNum'}++;
						my $doseNum = $casesData{$formerTopMargin}->{'doseNum'} // die;
						$casesData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $dose;
						# say "doses : $doseNum - $dose";
					}
				} elsif ($text eq 'Pla cebo' || $text eq 'Pla ceb o') {
					$casesData{$formerTopMargin}->{'doseNum'}++;
					my $doseNum = $casesData{$formerTopMargin}->{'doseNum'} // die;
					$casesData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = 'Placebo';
					# say "doses : $doseNum - $dose";
				} elsif ($text =~ /Page /) {
					last;
				} elsif ($text =~ /^.....2020\/$/ || $text =~ /^.....2021\/$/) {
					# say "$dNum | [$text]";
					$text =~ s/\///;
					my ($doseDate, $year, $month, $weekNumber) = convert_date($text);
					$casesData{$topMargin}->{'doseNumDate'}++;
					my $doseNumDate = $casesData{$topMargin}->{'doseNumDate'} // die;
					$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'doseDate'}   = $doseDate;
					$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'year'}       = $year;
					$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'month'}      = $month;
					$casesData{$topMargin}->{'doses'}->{$doseNumDate}->{'weekNumber'} = $weekNumber;
					# say "date : [$text] -> $doseDate, $year, $month, $weekNumber";
					$formerLine      = $text;
					$formerTopMargin = $topMargin;
				} else {
					if ($pageNum == 4376 && $firstAttempt == 1) {
						$casesGroupDone = 0;
						$firstAttempt = 0;
						goto process_div;
					} else {
						die "text : [$text]";
					}
				}
			}
		}
	}
	# p%casesData;
	# die;
	unless ($entryNum == $pageTotalPatients) {
		say "page $pageNum, $entryNum != $pageTotalPatients";
	}
	# die if $pageNum == 646;
	return %casesData;
}
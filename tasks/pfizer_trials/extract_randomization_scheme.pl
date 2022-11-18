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

# Original randomization files of the patients is here, page 1 to 4376.
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-randomization-sensitive.pdf&currentLanguage=en

# This script parses this file, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $randomizationPdfFile   = "public/pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-randomization-sensitive.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $randomizationPdfFile;
my $randomizationPdfFolder = "raw_data/pfizer_trials/randomization_scheme";
my $outputFolder           = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $randomizationPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$randomizationPdfFile\" \"$randomizationPdfFolder\"";
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
say "total entries   : " . keys %patients;

# Generates weekly stats, prints .CSV.
my %stats = ();
my $patientsToCutOff = 0;
open my $out, '>:utf8', "$outputFolder/pfizer_trial_randomization.csv";
say $out "number;patient id;sex;age (years);screening date;week number;";
for my $patientId (sort keys %patients) {
	my $randomizationMonth      = $patients{$patientId}->{'randomizationMonth'}      // die;
	my $randomizationDate       = $patients{$patientId}->{'randomizationDate'}       // die;
	my $randomizationWeekNumber = $patients{$patientId}->{'randomizationWeekNumber'} // die;
	$stats{$randomizationWeekNumber}->{'cases'}++;
	$stats{$randomizationWeekNumber}->{'month'} = $randomizationMonth if !exists $stats{$randomizationWeekNumber}->{'month'};
	if ($randomizationDate >= '20200720' && $randomizationDate <= '20201114') {
		$patientsToCutOff++;
	}
}
close $out;
say "patients to Nov. 14 2020 cut-off : [$patientsToCutOff]";

# Prints weekly stats.
open my $out2, '>:utf8', "$outputFolder/randomization_weekly_recruitment.csv";
say $out2 "month;week number;cases;";
for my $weekNumber (sort{$a <=> $b} keys %stats) {
	my $cases = $stats{$weekNumber}->{'cases'} // die;
	my $month = $stats{$weekNumber}->{'month'} // die;
	say $out2 "$month;$weekNumber;$cases;";
}
close $out2;

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_randomization.json";
print $out3 encode_json\%patients;
close $out3;

sub verify_pdf_structure {
	for my $htmlFile (glob "$randomizationPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 4376) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$randomizationPdfFolder/page$pageNum.html";
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

		# We then look for randomization dates.
		my %randomizationDates = parse_randomization_dates($pageTotalPatients, @divs);

		# We then look for the randomization groups.
		my %randomizationData  = parse_randomization_groups($pageNum, $pageTotalPatients, @divs);
		# p%patientsIds;
		# p%randomizationDates;
		# p%randomizationData;

		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $patientId               = $patientsIds{$topMargin}->{'patientId'}                      // die;
			my $randomizationDate       = $randomizationDates{$topMargin}->{'randomizationDate'}       // die;
			my $randomizationMonth      = $randomizationDates{$topMargin}->{'randomizationMonth'}      // die;
			my $randomizationWeekNumber = $randomizationDates{$topMargin}->{'randomizationWeekNumber'} // die;
			my $randomizationYear       = $randomizationDates{$topMargin}->{'randomizationYear'}       // die;
			my $randomizationGroup      = $randomizationData{$topMargin}->{'randomizationGroup'};
			# p$randomizationData{$topMargin};
			$patients{$patientId}->{'pageNum'}                 = $pageNum;
			$patients{$patientId}->{'randomizationDate'}       = $randomizationDate;
			$patients{$patientId}->{'randomizationMonth'}      = $randomizationMonth;
			$patients{$patientId}->{'randomizationWeekNumber'} = $randomizationWeekNumber;
			$patients{$patientId}->{'randomizationYear'}       = $randomizationYear;
			$patients{$patientId}->{'randomizationGroup'}      = $randomizationGroup;
			for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$topMargin}->{'doses'}}) {
				my $dose       = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'dose'}       // next;
				my $month      = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'month'}      // next;
				my $dosage     = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'dosage'};
				my $doseDate   = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'doseDate'};
				my $weekNumber = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'weekNumber'} // die;
				my $year       = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'year'}       // die;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'dose'}       = $dose;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'month'}      = $month;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'dosage'}     = $dosage;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'doseDate'}   = $doseDate;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'weekNumber'} = $weekNumber;
				$patients{$patientId}->{'doses'}->{$doseNum}->{'year'}       = $year;
			}
		}
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $pNum, $init) = (0, 0, 0);
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
					my $patientId = "$trialAndSiteData $text";
					$patientId =~ s/\^//;
					unless (length $patientId == 22) {
						$patientId =~ s/†//;
						# say "patientId : [$patientId]";
						die "patientId : [$patientId]" unless (length $patientId == 22);
					}
					# die;
					$pNum++;
					$patientsIds{$topMargin}->{'patientId'}          = $patientId;
					$patientsIds{$topMargin}->{'patientIdTopMargin'} = $topMargin;
					# say "$pNum | $patientId";
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

sub parse_randomization_dates {
	my ($pageTotalPatients, @divs) = @_;
	my %randomizationDates = ();
	my ($dNum, $pNum) = (0, 0);

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
			my ($randomizationDate, $randomizationYear, $randomizationMonth, $randomizationWeekNumber) = convert_date($date);
			$pNum++;
			my $style = $div->attr_get_i('style');
			my ($topMargin) = $style =~ /top:(.*)px;/;
			die unless looks_like_number $topMargin;
			$randomizationDates{$topMargin}->{'randomizationDateTopMargin'} = $topMargin;
			$randomizationDates{$topMargin}->{'randomizationDate'}          = $randomizationDate;
			$randomizationDates{$topMargin}->{'randomizationYear'}          = $randomizationYear;
			$randomizationDates{$topMargin}->{'randomizationMonth'}         = $randomizationMonth;
			$randomizationDates{$topMargin}->{'randomizationWeekNumber'}    = $randomizationWeekNumber;
			# say "$dNum | $randomizationDate";
		}
	}
	# p%randomizationDates;
	unless ($pNum == $pageTotalPatients) {
		die "$pNum != $pageTotalPatients";
	}
	return %randomizationDates;
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

sub parse_randomization_groups {
	my ($pageNum, $pageTotalPatients, @divs) = @_;
	my %randomizationData = ();
	my ($dNum, $pNum, $firstAttempt) = (0, 0, 1);
	my $randomizationGroupStart = 0;
	my $randomizationGroupDone  = 0;
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
		if ($text =~ /\// && $randomizationGroupStart == 1) {
			$randomizationGroupDone = 1;
		}
		process_div:
		if ($randomizationGroupDone == 0) {
			if (
					$text eq 'Pla cebo' || $text eq 'Placebo' || (
					($text =~ /^\(.. \μg\)$/ && $formerLine eq 'BNT162b1')
				)
			) {
				$pNum++;
				# say "$dNum | $text";
				$randomizationGroupStart = 1;
				if ($text =~ /^\(.. μg\)$/) {
					$randomizationData{$formerTopMargin}->{'randomizationGroup'}     = "BNT162b2 $text";
					$randomizationData{$formerTopMargin}->{'randomizationTopMargin'} = $formerTopMargin;
				} else {
					$randomizationData{$topMargin}->{'randomizationGroup'}     = "Placebo";
					$randomizationData{$topMargin}->{'randomizationTopMargin'} = $topMargin;
				}
			} elsif (
					$text eq 'Pla cebo' || $text eq 'Placebo' || (
					($text =~ /^\(.. \μg\)$/ && $formerLine eq 'BNT162b2')
				)
			) {
				$pNum++;
				# say "$dNum | $text";
				$randomizationGroupStart = 1;
				if ($text =~ /^\(.. μg\)$/) {
					$randomizationData{$formerTopMargin}->{'randomizationGroup'}     = "BNT162b2 $text";
					$randomizationData{$formerTopMargin}->{'randomizationTopMargin'} = $formerTopMargin;
				} else {
					$randomizationData{$topMargin}->{'randomizationGroup'}     = "Placebo";
					$randomizationData{$topMargin}->{'randomizationTopMargin'} = $topMargin;
				}
			}
			$formerLine = $text;
			$formerTopMargin = $topMargin;
		} else {
			if ($randomizationGroupDone == 1) {
				# say "$dNum | [$text]";
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				if ($text =~ /....2020\/ .....2020/ || $text =~ /....2020\/ .....2021/ || $text =~ /....2021\/ .....2021/) {
					my @dates = split '\/ ', $text;
					for my $date (@dates) {
						$date =~ s/\///;
						my ($doseDate, $year, $month, $weekNumber) = convert_date($date);
						$randomizationData{$topMargin}->{'doseNumDate'}++;
						my $doseNumDate = $randomizationData{$topMargin}->{'doseNumDate'} // die;
						$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'doseDate'}   = $doseDate;
						$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'year'}       = $year;
						$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'month'}      = $month;
						$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'weekNumber'} = $weekNumber;
						# say "date : [$date] -> $doseDate, $year, $month, $weekNumber";
					}
					$formerLine = $text;
					$formerTopMargin = $topMargin;
				} elsif ($text =~ /^BNT162b\d BNT162b\d$/) {
					my @doses = split ' ', $text;
					for my $dose (@doses) {
						$randomizationData{$formerTopMargin}->{'doseNum'}++;
						my $doseNum = $randomizationData{$formerTopMargin}->{'doseNum'} // die;
						$randomizationData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $dose;
						# say "doses : $doseNum - $dose";
					}
				} elsif ($text =~ /^BNT162b\d/) {
					$randomizationData{$formerTopMargin}->{'doseNum'}++;
					my $doseNum = $randomizationData{$formerTopMargin}->{'doseNum'} // die;
					$randomizationData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $text;
				} elsif ($text =~ /^\(.. μg\)$/ || $text =~ /^\(... μg\)$/) {
					$randomizationData{$formerTopMargin}->{'dosageNum'}++;
					my $dosageNum = $randomizationData{$formerTopMargin}->{'dosageNum'} // die;
					$randomizationData{$formerTopMargin}->{'doses'}->{$dosageNum}->{'dosage'} = $text;
					# p$randomizationData{$formerTopMargin}->{'doses'};
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
						$randomizationData{$formerTopMargin}->{'dosageNum'}++;
						my $dosageNum = $randomizationData{$formerTopMargin}->{'dosageNum'} // die;
						$randomizationData{$formerTopMargin}->{'doses'}->{$dosageNum}->{'dosage'} = $dosage;
						# say "dosage : $dosage";
					}
					# p$randomizationData{$formerTopMargin}->{'doses'};
					# say "$formerLine - $dosageNum - $text";
					# die;
				} elsif ($text =~ /Placebo /) {
					my @doses = split ' ', $text;
					for my $dose (@doses) {
						$randomizationData{$formerTopMargin}->{'doseNum'}++;
						my $doseNum = $randomizationData{$formerTopMargin}->{'doseNum'} // die;
						$randomizationData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = $dose;
						# say "doses : $doseNum - $dose";
					}
				} elsif ($text eq 'Pla cebo' || $text eq 'Pla ceb o') {
					$randomizationData{$formerTopMargin}->{'doseNum'}++;
					my $doseNum = $randomizationData{$formerTopMargin}->{'doseNum'} // die;
					$randomizationData{$formerTopMargin}->{'doses'}->{$doseNum}->{'dose'} = 'Placebo';
					# say "doses : $doseNum - $dose";
				} elsif ($text =~ /Page /) {
					last;
				} elsif ($text =~ /^.....2020\/$/ || $text =~ /^.....2021\/$/) {
					# say "$dNum | [$text]";
					$text =~ s/\///;
					my ($doseDate, $year, $month, $weekNumber) = convert_date($text);
					$randomizationData{$topMargin}->{'doseNumDate'}++;
					my $doseNumDate = $randomizationData{$topMargin}->{'doseNumDate'} // die;
					$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'doseDate'}   = $doseDate;
					$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'year'}       = $year;
					$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'month'}      = $month;
					$randomizationData{$topMargin}->{'doses'}->{$doseNumDate}->{'weekNumber'} = $weekNumber;
					# say "date : [$text] -> $doseDate, $year, $month, $weekNumber";
					$formerLine      = $text;
					$formerTopMargin = $topMargin;
				} else {
					if ($pageNum == 4376 && $firstAttempt == 1) {
						$randomizationGroupDone = 0;
						$firstAttempt = 0;
						goto process_div;
					} else {
						die "text : [$text]";
					}
				}
			}
		}
	}
	# p%randomizationData;
	# die;
	unless ($pNum == $pageTotalPatients) {
		# say "page $pageNum, $pNum != $pageTotalPatients";
	}
	# die if $pageNum == 646;
	return %randomizationData;
}
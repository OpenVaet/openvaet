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

# Original randomization files of the patients is here, page 1 to 4412.
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-randomization-sensitive.pdf&currentLanguage=en

# This script parses this file, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $randomizationPdfFile   = "public/pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-randomization-sensitive.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $randomizationPdfFile;
my $randomizationPdfFolder = "raw_data/pfizer_trials/randomization_scheme_1";
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

# We then verify that we have as expected 4412 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 22 to 4412 (table "All Subjects").
my %patients = ();
my $totalPatients = 0;
extract_all_subjects_table();
# p%patients;
say "totalPatients   : $totalPatients";
say "total entries   : " . keys %patients;

# Generates weekly stats, prints .CSV.
my %stats = ();
my $patientsFromP1ToCutOff = 0;
my $doses1FromP1ToCutOff = 0;
my $doses2FromP1ToCutOff = 0;
my $patientsToCutOff = 0;
my $noDoseData = 0;
open my $out, '>:utf8', "$outputFolder/pfizer_trial_randomization_1.csv";
say $out "number;patient id;sex;age (years);screening date;week number;";
for my $uSubjectId (sort keys %patients) {
	my $randomizationMonth      = $patients{$uSubjectId}->{'randomizationMonth'}      // die;
	my $randomizationDate       = $patients{$uSubjectId}->{'randomizationDate'}       // die;
	my $dose1Date               = $patients{$uSubjectId}->{'doses'}->{'1'}->{'doseDate'};
	my $dose2Date               = $patients{$uSubjectId}->{'doses'}->{'2'}->{'doseDate'};
	my $randomizationWeekNumber = $patients{$uSubjectId}->{'randomizationWeekNumber'} // die;
	$stats{$randomizationWeekNumber}->{'cases'}++;
	$stats{$randomizationWeekNumber}->{'month'} = $randomizationMonth if !exists $stats{$randomizationWeekNumber}->{'month'};
	if ($randomizationDate >= '20200720' && $randomizationDate <= '20201114') {
		$patientsFromP1ToCutOff++;
	}
	if ($randomizationDate <= '20201114') {
		$patientsToCutOff++;
	}
	if ($dose1Date) {

		if ($dose1Date >= '20200720' && $dose1Date <= '20201114') {
			$doses1FromP1ToCutOff++;
		}
	} else {
		$noDoseData++;
	}
	if ($dose2Date) {

		if ($dose2Date >= '20200720' && $dose2Date <= '20201107') {
			$doses2FromP1ToCutOff++;
		}
	}
}
close $out;
say "patients from July 20 to Nov. 14 2020 cut-off : [$patientsFromP1ToCutOff]";
say "patients to Nov. 14 2020 cut-off : [$patientsToCutOff]";
say "doses 1 from July 20 to Nov. 14 2020 cut-off : [$doses1FromP1ToCutOff] ($noDoseData without dose 1)";
say "doses 2 from July 20 to Nov. 8 2020 cut-off : [$doses2FromP1ToCutOff]";

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
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_randomization_1.json";
print $out3 encode_json\%patients;
close $out3;

sub verify_pdf_structure {
	for my $htmlFile (glob "$randomizationPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 4412) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		next if $pageNum == 37;
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
		my %patientsIds        = parse_unique_subject_ids(@divs);
		# p%patientsIds;
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;

		# We then look for randomization dates.
		my %randomizationDates = parse_randomization_dates($pageNum, $pageTotalPatients, @divs);
		# p%randomizationDates;

		# We then look for the randomization groups.
		my %randomizationData  = parse_randomization_groups($pageNum, $pageTotalPatients, @divs);
		# p%randomizationData;
		# die;
		my $noDose = 0;
		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $uSubjectId              = $patientsIds{$topMargin}->{'uSubjectId'}                     // die;
			my ($subjectId)             = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
			my $randomizationDate       = $randomizationDates{$topMargin}->{'randomizationDate'}       // die;
			my $randomizationMonth      = $randomizationDates{$topMargin}->{'randomizationMonth'}      // die;
			my $randomizationWeekNumber = $randomizationDates{$topMargin}->{'randomizationWeekNumber'} // die;
			my $randomizationYear       = $randomizationDates{$topMargin}->{'randomizationYear'}       // die;
			my $randomizationGroup      = $randomizationData{$topMargin}->{'randomizationGroup'};
			# p$randomizationData{$topMargin};
			$patients{$subjectId}->{'pageNum'}                 = $pageNum;
			$patients{$subjectId}->{'randomizationDate'}       = $randomizationDate;
			$patients{$subjectId}->{'uSubjectId'}              = $uSubjectId;
			$patients{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
			$patients{$subjectId}->{'randomizationMonth'}      = $randomizationMonth;
			$patients{$subjectId}->{'randomizationWeekNumber'} = $randomizationWeekNumber;
			$patients{$subjectId}->{'randomizationYear'}       = $randomizationYear;
			$patients{$subjectId}->{'randomizationGroup'}      = $randomizationGroup;
			for my $doseNum (sort{$a <=> $b} keys %{$randomizationData{$topMargin}->{'doses'}}) {
				my $month      = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'month'}      // next;
				my $dose       = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'dose'};
				my $doseDate   = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'doseDate'};
				my $weekNumber = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'weekNumber'} // die;
				my $year       = $randomizationData{$topMargin}->{'doses'}->{$doseNum}->{'year'}       // die;
				$patients{$subjectId}->{'doses'}->{$doseNum}->{'dose'}       = $dose;
				$patients{$subjectId}->{'doses'}->{$doseNum}->{'month'}      = $month;
				$patients{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'}   = $doseDate;
				$patients{$subjectId}->{'doses'}->{$doseNum}->{'weekNumber'} = $weekNumber;
				$patients{$subjectId}->{'doses'}->{$doseNum}->{'year'}       = $year;
			}
			$noDose++ if !exists $randomizationData{$topMargin}->{'doses'};
		}
		die if $noDose > 5;
	}
}

sub parse_unique_subject_ids {
	my @divs = @_;
	my %subjectIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialData, $siteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
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

sub parse_randomization_dates {
	my ($pageNum, $pageTotalPatients, @divs) = @_;
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
			my $style = $div->attr_get_i('style');
			my ($topMargin) = $style =~ /top:(.*)px;/;
			die unless looks_like_number $topMargin;
			next if exists $randomizationDates{$topMargin};
			$pNum++;
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
		p%randomizationDates;
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
	my ($dNum, $pNum) = (0, 0);
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
		my @words = split ' ', $text;
		for my $word (@words) {
			if (
					$word eq 'Placebo' ||
					$word =~ /^BNT162b\d$/
				)
			{
				$randomizationData{$topMargin}->{'randomizationGroupNum'}++;
				my $randomizationGroupNum = $randomizationData{$topMargin}->{'randomizationGroupNum'} // die;
				# say "$dNum | $word";
				$randomizationData{$topMargin}->{'entries'}->{$randomizationGroupNum}->{'doseData'}   = $word;
			} elsif ($word =~ /Page /) {
				last;
			} elsif ($word =~ /^.....2020$/ || $word =~ /^.....2021$/) {
				# say "$dNum | [$word]";
				$word =~ s/\///;
				my ($doseDate, $year, $month, $weekNumber) = convert_date($word);
				$randomizationData{$topMargin}->{'doseNumDate'}++;
				my $doseNumDate = $randomizationData{$topMargin}->{'doseNumDate'} // die;
				$randomizationData{$topMargin}->{'entries'}->{$doseNumDate}->{'doseDate'}   = $doseDate;
				$randomizationData{$topMargin}->{'entries'}->{$doseNumDate}->{'year'}       = $year;
				$randomizationData{$topMargin}->{'entries'}->{$doseNumDate}->{'month'}      = $month;
				$randomizationData{$topMargin}->{'entries'}->{$doseNumDate}->{'weekNumber'} = $weekNumber;
				# say "date : [$word] -> $doseDate, $year, $month, $weekNumber";
				$formerLine      = $word;
				$formerTopMargin = $topMargin;
			}
		}
	}

	# Reformats doses.
	for my $topMargin (sort{$a <=> $b} keys %randomizationData) {
		my $randomizationGroup = $randomizationData{$topMargin}->{'entries'}->{'1'}->{'doseData'} // die;
		$randomizationData{$topMargin}->{'randomizationGroup'}     = $randomizationGroup;
		my $dNum = 0;
		for my $doseNum (2 .. 3) {
			$dNum++;
			my $doseDate = $randomizationData{$topMargin}->{'entries'}->{$doseNum}->{'doseDate'} // next;
			my $doseData = $randomizationData{$topMargin}->{'entries'}->{$doseNum}->{'doseData'};
			my $year = $randomizationData{$topMargin}->{'entries'}->{$doseNum}->{'year'} // die;
			my $month = $randomizationData{$topMargin}->{'entries'}->{$doseNum}->{'month'} // die;
			my $weekNumber = $randomizationData{$topMargin}->{'entries'}->{$doseNum}->{'weekNumber'} // die;
			$randomizationData{$topMargin}->{'doses'}->{$dNum}->{'doseDate'}   = $doseDate;
			$randomizationData{$topMargin}->{'doses'}->{$dNum}->{'year'}       = $year;
			$randomizationData{$topMargin}->{'doses'}->{$dNum}->{'dose'}       = $doseData;
			$randomizationData{$topMargin}->{'doses'}->{$dNum}->{'month'}      = $month;
			$randomizationData{$topMargin}->{'doses'}->{$dNum}->{'weekNumber'} = $weekNumber;

		}
		delete $randomizationData{$topMargin}->{'entries'};
	}

	# p%randomizationData;
	# die;
	# die if $pageNum == 646;
	return %randomizationData;
}
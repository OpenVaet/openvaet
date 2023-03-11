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
my %patients      = ();
my $totalPatients = 0;
my %patientsIds   = ();
my %preCutoff     = ();
extract_all_subjects_table();
# p%patients;
say "totalPatients   : $totalPatients";
say "pre-cut-off     : " . keys %preCutoff;

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_cases_1.json";
print $out3 encode_json\%patients;
close $out3;
open my $out4, '>:utf8', "$outputFolder/pre_cut_off_pdf_cases.json";
print $out4 encode_json\%preCutoff;
close $out4;

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
		%patientsIds = ();
		my $htmlFile = "$casesPdfFolder/page$pageNum.html";
		# say "*" x 50;
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

		open my $out, '>:utf8', 'tmp.html';
		print $out $content;
		close $out;

		# We first extract all the patient ids in the page, so we known how many to expect.
		%patientsIds           = parse_patients_ids(@divs);
		my $pageTotalPatients  = keys %patientsIds;
		die unless $pageTotalPatients;

		# Fetching first swabs diagnoses.
		my %firstSwabs = parse_swabs($pageTotalPatients, @divs);

		# We then look for cases dates.
		my %swabDates = parse_swab_dates($pageTotalPatients, @divs);

		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			$totalPatients++;
			my $uSubjectId              = $patientsIds{$topMargin}->{'uSubjectId'} // die;
			my ($subjectId) = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
			die unless $subjectId;
			my $entryNum               = $patientsIds{$topMargin}->{'entryNum'}    // die;

			# Incrementing earlier swabs data.
			die unless keys %{$firstSwabs{$topMargin}} == 3;
			for my $tM (sort keys %{$firstSwabs{$topMargin}}) {
				my $visit1NBindAssay = $firstSwabs{$topMargin}->{'visit1NBindAssay'} // die;
				my $visit1NaaT = $firstSwabs{$topMargin}->{'visit1NaaT'} // die;
				my $visit2NaaT = $firstSwabs{$topMargin}->{'visit2NaaT'} // die;
				$patients{$subjectId}->{'visit1NBindAssay'} = $visit1NBindAssay;
				$patients{$subjectId}->{'visit1NaaT'} = $visit1NaaT;
				$patients{$subjectId}->{'visit2NaaT'} = $visit2NaaT;
			}
			die unless
				$patients{$subjectId}->{'visit1NBindAssay'} &&
				$patients{$subjectId}->{'visit1NaaT'} &&
				$patients{$subjectId}->{'visit2NaaT'};
			my $swabDate        = $swabDates{$topMargin}->{'swabDate'}        // die;
			my $casesMonth      = $swabDates{$topMargin}->{'casesMonth'}      // die;
			my $casesWeekNumber = $swabDates{$topMargin}->{'casesWeekNumber'} // die;
			my $casesYear       = $swabDates{$topMargin}->{'casesYear'}       // die;
			$patients{$subjectId}->{'uSubjectId'}      = $uSubjectId;
			$patients{$subjectId}->{'swabDate'}        = $swabDate;
			$patients{$subjectId}->{'pageNum'}         = $pageNum;
			$patients{$subjectId}->{'entryNum'}        = $entryNum;
			$patients{$subjectId}->{'swabDate'}        = $swabDate;
			$patients{$subjectId}->{'casesMonth'}      = $casesMonth;
			$patients{$subjectId}->{'casesWeekNumber'} = $casesWeekNumber;
			$patients{$subjectId}->{'casesYear'}       = $casesYear;
			if ($swabDate <= 20201114) {
				$preCutoff{$subjectId} = $swabDate;
			}
			# p$patients{$subjectId};
			# die;
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
			} else {
				if ($trialAndSiteData) {
					my $uSubjectId = "$trialAndSiteData $text";
					$uSubjectId =~ s/\^//;
					unless (length $uSubjectId == 22) {
						$uSubjectId =~ s/†//;
						unless (length $uSubjectId == 22) {
							($uSubjectId) = split ' \(', $uSubjectId;
							die "uSubjectId : [$uSubjectId]" unless (length $uSubjectId == 22);
						}
					}
					$entryNum++;
					$patientsIds{$topMargin}->{'entryNum'}            = $entryNum;
					$patientsIds{$topMargin}->{'uSubjectId'}          = $uSubjectId;
					$patientsIds{$topMargin}->{'uSubjectIdTopMargin'} = $topMargin;
					$trialAndSiteData = undef;
					$topMargin = undef;
				}
			}
		}
	}
	unless ($init == keys %patientsIds) {
		p%patientsIds;
		die "$init != " . keys %patientsIds;
	}
	return %patientsIds;
}

sub parse_swab_dates {
	my ($pageTotalPatients, @divs) = @_;
	my %swabDates = ();
	my ($dNum, $entryNum) = (0, 0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			# say "$dNum | $word";
			if ((
					(
						$word =~ /^.....2020$/ ||
						(
							$word =~ /^..-.. .....2020$/ ||
							$word =~ />.. .....2020$/
						) ||
						(
							$word =~ /^^..-.. .....2020 \d\d\d\d\d\d/ ||
							$word =~ />.. .....2020 \d\d\d\d\d\d/
						)
					) ||
					(
						$word =~ /^.....2021$/ ||
						(
							$word =~ /^..-.. .....2021$/ ||
							$word =~ />.. .....2021$/
						) ||
						(
							$word =~ /^^..-.. .....2021 \d\d\d\d\d\d/ ||
							$word =~ />.. .....2021 \d\d\d\d\d\d/
						)
					)
				) && $word !~ /Page/) {
				my ($date) = $word =~ /(.....2020)/;
				unless ($date) {
					($date) = $word =~ /(.....2021)/;
				}
				die unless $date;
				my ($swabDate, $casesYear, $casesMonth, $casesWeekNumber) = convert_date($date);
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				next if exists $swabDates{$topMargin}->{'swabDate'};
				$entryNum++;
				$swabDates{$topMargin}->{'swabDateTopMargin'} = $topMargin;
				$swabDates{$topMargin}->{'swabDate'}          = $swabDate;
				$swabDates{$topMargin}->{'casesYear'}          = $casesYear;
				$swabDates{$topMargin}->{'casesMonth'}         = $casesMonth;
				$swabDates{$topMargin}->{'casesWeekNumber'}    = $casesWeekNumber;
			}
		}
	}
	return %swabDates;
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

sub parse_swabs {
	my ($pageTotalPatients, @divs) = @_;
	my %firstSwabs = ();
	my ($dNum) = (0);

	# The date has two possible formats ; date alone, or age group & date collated.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Abbreviations:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			# say "word : [$word]";
			if ($word =~ /(...)\/(...)\/(...)/) {
				my ($visit1NBindAssay, $visit1NaaT, $visit2NaaT) = $word =~ /(...)\/(...)\/(...)/;
				# say "$visit1NBindAssay, $visit1NaaT, $visit2NaaT";
				my $style = $div->attr_get_i('style');
				my ($topMargin) = $style =~ /top:(.*)px;/;
				die unless looks_like_number $topMargin;
				$firstSwabs{$topMargin}->{'visit1NBindAssay'} = $visit1NBindAssay;
				$firstSwabs{$topMargin}->{'visit1NaaT'} = $visit1NaaT;
				$firstSwabs{$topMargin}->{'visit2NaaT'} = $visit2NaaT;
			} elsif ($word =~ /^(...)\/(...)$/) {
				my ($visit1NaaT, $visit2NaaT) = $word =~ /(...)\/(...)/;
				if (
					($visit1NaaT eq 'Neg' || $visit1NaaT eq 'Pos' || $visit1NaaT eq 'Unk') &&
					($visit2NaaT eq 'Neg' || $visit2NaaT eq 'Pos' || $visit2NaaT eq 'Unk')
				) {
					# say "$visit1NaaT, $visit2NaaT";
					my $style = $div->attr_get_i('style');
					my ($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					next if exists $firstSwabs{$topMargin}->{'visit1NaaT'};
					$firstSwabs{$topMargin}->{'visit1NaaT'} = $visit1NaaT;
					$firstSwabs{$topMargin}->{'visit2NaaT'} = $visit2NaaT;
				}
			} elsif ($word =~ /^(...)\/$/) {
				my ($visit1NBindAssay) = $word =~ /(...)\//;
				if ($visit1NBindAssay eq 'Neg' || $visit1NBindAssay eq 'Pos' || $visit1NBindAssay eq 'Unk') {
					# say "$visit1NBindAssay";
					my $style = $div->attr_get_i('style');
					my ($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					next if exists $firstSwabs{$topMargin}->{'visit1NBindAssay'};
					$firstSwabs{$topMargin}->{'visit1NBindAssay'} = $visit1NBindAssay;
				}
			}
		}
	}
	unless (keys %firstSwabs == $pageTotalPatients) {
		p%firstSwabs;
		my $err = keys %firstSwabs;
		$err .=  " != $pageTotalPatients";
		say $err;
		die;
	}
	return %firstSwabs;
}
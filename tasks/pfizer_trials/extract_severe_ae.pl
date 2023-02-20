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

# File containing the Adverse effects as of April 2021
my $file         = "public/pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-adverse-events.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $file;
my $saePdfFolder = "raw_data/pfizer_trials/sae";
my $outputFolder = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $saePdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$file\" \"$saePdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 3645 HTML pages resulting from the extraction.
my %htmlPages  = ();
my %pageText   = ();
verify_pdf_structure();
extract_data();
my %subjectAES = ();
my %currentSymptomData = ();
my (
	$ageGroup, $systemOrganClass,
	$trialSiteId, $subjectId,
	$symptoms, $doseNumber,
	$onsetDate, $relativeDaysDuration,
	$toxicityGrade, $vaxRelated,
	$outcome, $outcomeDate,
	$lastPageNum, $lastTopMargin
);
my ($subjectNumber, $adverseEffectSetNumber, $adverseEffectNumber) = (0, 1, 1);
parse_pages_structure();
parse_pages_symptoms();

my %subjectAESFormatted = ();
for my $subjectNumber (sort{$a <=> $b} keys %subjectAES) {
	my $subjectId = $subjectAES{$subjectNumber}->{'subjectId'} // die;
	$subjectId =~ s/\^//;
	$subjectAESFormatted{$subjectId} = \%{$subjectAES{$subjectNumber}};
	$subjectAESFormatted{$subjectId}->{'subjectId'} = $subjectId;
}
open my $out, '>:utf8', 'public/doc/pfizer_phase_1/20210401_serious_adverse_effects_16_2_7_5.json';
print $out encode_json\%subjectAESFormatted;
close $out;
# p%subjectAES;
# p%stats;

sub verify_pdf_structure {
	for my $htmlFile (glob "$saePdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 3645) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}


sub extract_data {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		next unless $pageNum >= 3518;
		my $htmlFile = "$saePdfFolder/page$pageNum.html";
		STDOUT->printflush("\rParsing HTML to Text [$pageNum]");
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
		parse_page_text($pageNum, @divs);
		# p%pageText;
		# die;
		last if $pageNum == 3618;
	}
	say "";
}

sub parse_page_text {
	my ($pageNum, @divs) = @_;
	my ($yesNoFound) = (0);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /FDA-CBER-/;
		last if $text =~ /Page/;
		last if $text =~ /Abbreviations:/;
		my $style = $div->attr_get_i('style');
		my ($leftMargin) = $style =~ /left:(.*)px; top:/;
		my ($topMargin) = $style =~ /top:(.*)px;/;
		die unless looks_like_number $leftMargin && looks_like_number $topMargin;
		$pageText{$pageNum}->{$topMargin}->{'totalLeft'}+= $leftMargin;
		my $totalLeft = $pageText{$pageNum}->{$topMargin}->{'totalLeft'} // die;
		my @words = split ' ', $text;
		for my $word (@words) {
			unless ($yesNoFound) {
				if ($word eq '>55/' || $word eq '16-55/' || $word eq '18-55/' || ($word =~ /^\d\d\d\d$/ && $totalLeft <= 100) || ($word   =~ /^\d\d\d\d\d\d\d\d/ && $totalLeft == 94)) {
					$yesNoFound = 1;
				}
			}
			if ($yesNoFound == 1) {
				if (
					$word eq 'O'        || $word =~ /NA\//            ||
					$word eq 'Y/N'      || $word eq 'Action:'         ||
					$word eq 'Cause'    || $word =~ /P\/TC/           ||
					$word eq 'C4591001' || $word eq 'Investigational' ||
					$word eq 'SAE/Imm'  || $word eq 'Onset'           ||
					$word eq 'Dur'      || $word eq 'Toxicity'        ||
					$word eq 'Vax'      || $word eq 'of'              ||
					$word eq 'Vaccine'  || $word eq 'Dose/'           ||
					$word eq 'Outcome'  || $word eq 'AE'              ||
					$word eq 'Date'     || $word eq 'Subject'         ||
					$word eq '(End'     || $word eq 'Date)'           ||
					$word eq '(Yes/No)' || $word eq 'NA'
				) {
					next;
				} else {
					$pageText{$pageNum}->{$topMargin}->{'entryNum'}++;
					my $entryNum = $pageText{$pageNum}->{$topMargin}->{'entryNum'} // die;
					$pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'totalLeft'} = $totalLeft;
					$pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'word'}      = $word;
					# say "$dNum | $entryNum | $topMargin | $leftMargin | $word";
				}
			}
			if ($word eq '(Yes/No)') {
				$yesNoFound = 1;
			}
		}
		delete $pageText{$pageNum}->{$topMargin} unless exists $pageText{$pageNum}->{$topMargin}->{'entries'};
	}
	die unless $yesNoFound;
}

sub parse_pages_structure {
	for my $pageNum (sort{$a <=> $b} keys %pageText) {
		STDOUT->printflush("\rParsing Structure    [$pageNum]");
		# say "*" x 50;
		# say "*" x 50;
		# say "pageNum : $pageNum";
		# say "*" x 50;
		# say "*" x 50;
		for my $topMargin (sort{$a <=> $b} keys %{$pageText{$pageNum}}) {
			for my $entryNum (sort{$a <=> $b} keys %{$pageText{$pageNum}->{$topMargin}->{'entries'}}) {
				my $totalLeft = $pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'totalLeft'} // die;
				my $word      = $pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'word'}      // die;
				# say "$topMargin - $totalLeft - $entryNum - [$word]";
				if ($word eq '>55/' || $word eq '16-55/' || $word eq '18-55/') {
					if ($subjectNumber) {
						# Finalizing current symptom data.
						# say "adverseEffectSetNumber : $adverseEffectSetNumber";
						# p%currentSymptomData;
						finalize_patient($pageNum, $topMargin);
					}

					# Initiating new subject.
					$subjectNumber++;
					%currentSymptomData   = ();
					$ageGroup             = $word;
					$systemOrganClass     = undef;
					$trialSiteId          = undef;
					$subjectId            = undef;
					$onsetDate            = undef;
					$adverseEffectSetNumber    = 1;
					$adverseEffectNumber        = 1;
					$subjectAES{$subjectNumber}->{'subjectFromPage'}      = $pageNum;
					$subjectAES{$subjectNumber}->{'subjectFromTopMargin'} = $topMargin;
				} elsif (
					$word eq 'INFEC' ||
					$word eq 'HEPAT' ||
					$word eq 'PSYCH' ||
					$word eq 'INJ&P' ||
					$word eq 'CARD'  ||
					$word eq 'VASC'  ||
					$word eq 'GENRL' ||
					$word eq 'METAB' ||
					$word eq 'REPRO' ||
					$word eq 'BLOOD' ||
					$word eq 'PREG'  ||
					$word eq 'SURG'  ||
					$word eq 'EAR'   ||
					$word eq 'EYE'   ||
					$word eq 'IMMUN' ||
					$word eq 'INV'   ||
					$word eq 'NEOPL' ||
					$word eq 'SOCCI' ||
					$word eq 'RENAL' ||
					$word eq 'GENRL' ||
					$word eq 'GASTR' ||
					$word eq 'NERV'  ||
					$word eq 'MUSC'  ||
					$word eq 'CONG'  ||
					$word eq 'RESP'
				) {
					if ($systemOrganClass) {
						if ($onsetDate) {
							# Finalizing current symptom data.
							$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'}  = $pageNum;
							$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}   = $topMargin;
						}
						# Setting former symptoms set limit.
						$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToTop'}    = $topMargin;
						$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToPage'}   = $pageNum;

						# say "--> $subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $adverseEffectSetNumber - $doseNumber - $onsetDate - $relativeDaysDuration - $toxicityGrade - $vaxRelated - $outcome - $outcomeDate - $symptoms";
						$adverseEffectSetNumber++;
					}
					$systemOrganClass     = $word;
					$onsetDate            = undef;
					$adverseEffectNumber        = 1;
					$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetFromPage'} = $pageNum;
					$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetFromTop'}  = $topMargin;
				} elsif ($word =~ /^\d\d\d\d$/ && $totalLeft <= 100) {
					$trialSiteId = $word;
				} elsif ($word   =~ /^\d\d\d\d\d\d\d\d/ && $totalLeft == 94) {
					$subjectId   = $word;
					# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
				} elsif (($word =~ /^\d\d...\d\d\d\d$/ || $word =~ /^...2020$/ || $word =~ /^...2021$/)) {
					if ($onsetDate) {
						# Finalizing current symptom data.
						$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'}  = $pageNum;
						$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}   = $topMargin;

						$adverseEffectNumber++;
					}
					$onsetDate       = $word;
					$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'systemOrganClass'} = $systemOrganClass;
					$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'onsetDate'}        = $onsetDate;
					$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromPage'}  = $pageNum;
					$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromTop'}   = $topMargin;
					# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
				} else {
					next;
				}
			}
			$lastTopMargin = $topMargin;
		}
		$lastPageNum = $pageNum;
	}
	$lastTopMargin += 1;
	finalize_patient($lastPageNum, $lastTopMargin);
}

sub finalize_patient {
	my ($pageNum, $topMargin) = @_;
	if (exists $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}) {
		$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'} = $pageNum;
		$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}  = $topMargin;

		# Setting former symptoms set limit.
		$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToTop'}  = $topMargin;
		$currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToPage'} = $pageNum;
	} else {

		# Some false positives are occuring on symptoms.
		die if $adverseEffectSetNumber == 1;
		delete $currentSymptomData{$adverseEffectSetNumber};
	}

	# Finalizing subject's syptoms.
	$subjectAES{$subjectNumber}->{'subjectToTopMargin'}   = $topMargin;
	$subjectAES{$subjectNumber}->{'subjectToPage'}        = $pageNum;
	$subjectAES{$subjectNumber}->{'trialSiteId'}          = $trialSiteId;
	$subjectAES{$subjectNumber}->{'subjectId'}            = $subjectId;
	for my $adverseEffectSetNumber (sort{$a <=> $b} keys %currentSymptomData) {
		my $symptomSetFromTop  = $currentSymptomData{$adverseEffectSetNumber}->{'symptomSetFromTop'}  // die;
		my $symptomSetFromPage = $currentSymptomData{$adverseEffectSetNumber}->{'symptomSetFromPage'} // die;
		my $symptomSetToTop    = $currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToTop'}    // die;
		my $symptomSetToPage   = $currentSymptomData{$adverseEffectSetNumber}->{'symptomSetToPage'}   // die;
		$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'symptomSetFromTop'}  = $symptomSetFromTop;
		$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'symptomSetFromPage'} = $symptomSetFromPage;
		$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'symptomSetToTop'}    = $symptomSetToTop;
		$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'symptomSetToPage'}   = $symptomSetToPage;
		for my $adverseEffectNumber (sort{$a <=> $b} keys %{$currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}}) {
			my $symptomFromTop   = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromTop'}   // die;
			my $symptomFromPage  = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromPage'}  // die;
			my $symptomToTop     = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}     // die;
			my $symptomToPage    = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'}    // die;
			my $systemOrganClass = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'systemOrganClass'} // die;
			my $onsetDate        = $currentSymptomData{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'onsetDate'}        // die;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'systemOrganClass'} = $systemOrganClass;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'severe'}           = 'Yes';
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'onsetDate'}        = $onsetDate;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromTop'}   = $symptomFromTop;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromPage'}  = $symptomFromPage;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}     = $symptomToTop;
			$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'}    = $symptomToPage;
		}
	}
	# p$subjectAES{$subjectNumber};
	die unless $trialSiteId && $subjectId;
}

sub parse_pages_symptoms {
	for my $subjectNumber (sort{$a <=> $b} keys %subjectAES) {
		for my $adverseEffectSetNumber (sort{$a <=> $b} keys %{$subjectAES{$subjectNumber}->{'adverseEffectsSets'}}) {
			for my $adverseEffectNumber (sort{$a <=> $b} keys %{$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}}) {
				$symptoms             = undef;
				$doseNumber           = undef;
				$relativeDaysDuration = undef;
				$vaxRelated           = undef;
				$toxicityGrade        = undef;
				$outcome              = undef;
				$outcomeDate          = undef;
				my $symptomFromPage = $subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromPage'} // die;
				my $symptomFromTop  = $subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomFromTop'}  // die;
				my $symptomToPage   = $subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToPage'}   // die;
				my $symptomToTop    = $subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'symptomToTop'}    // die;
				parse_symptoms_from_text($subjectNumber, $adverseEffectSetNumber, $adverseEffectNumber, $symptomFromPage, $symptomFromTop, $symptomToPage, $symptomToTop);
			}
		}
		# p$subjectAES{$subjectNumber};
		# die;
	}
}

sub parse_symptoms_from_text {
	my ($subjectNumber, $adverseEffectSetNumber, $adverseEffectNumber, $fromPage, $fromTop, $toPage, $toTop) = @_;
	# say "";
	# say "*" x 50;
	# say "$fromPage, $fromTop, $toPage, $toTop";
	my $hasStarted = 0;
	for my $pageNum (sort{$a <=> $b} keys %pageText) {
		next unless $fromPage <= $pageNum && $pageNum <= $toPage;
		# say "pageNum -> $pageNum";
		for my $topMargin (sort{$a <=> $b} keys %{$pageText{$pageNum}}) {
			if ($fromPage == $toPage) {
				next unless $fromTop <= $topMargin && $topMargin < $toTop;
			} else {
				if ($pageNum == $fromPage) {
					next unless $fromTop <= $topMargin;
				} else {
					next unless $topMargin < $toTop;
				}
			}
			# say "topMargin -> $topMargin";
			for my $entryNum (sort{$a <=> $b} keys %{$pageText{$pageNum}->{$topMargin}->{'entries'}}) {
				my $totalLeft = $pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'totalLeft'} // die;
				my $word      = $pageText{$pageNum}->{$topMargin}->{'entries'}->{$entryNum}->{'word'}      // die;
				unless (
					$word eq '>55/'   ||
					$word eq '16-55/' ||
					$word eq '18-55/' ||
					$word eq 'INFEC'  ||
					$word eq 'HEPAT'  ||
					$word eq 'PSYCH'  ||
					$word eq 'INJ&P'  ||
					$word eq 'CARD'   ||
					$word eq 'VASC'   ||
					$word eq 'GENRL'  ||
					$word eq 'METAB'  ||
					$word eq 'REPRO'  ||
					$word eq 'BLOOD'  ||
					$word eq 'PREG'   ||
					$word eq 'SURG'   ||
					$word eq 'EAR'    ||
					$word eq 'EYE'    ||
					$word eq 'IMMUN'  ||
					$word eq 'INV'    ||
					$word eq 'NEOPL'  ||
					$word eq 'SOCCI'  ||
					$word eq 'RENAL'  ||
					$word eq 'GENRL'  ||
					$word eq 'GASTR'  ||
					$word eq 'NERV'   ||
					$word eq 'MUSC'   ||
					$word eq 'CONG'   ||
					$word eq 'RESP'   ||
					$word =~ /^\d\d...\d\d\d\d$/ ||
					$word =~ /^...2020$/ ||
					$word =~ /^...2021$/ ||
					($word =~ /^\d\d\d\d$/ && $totalLeft <= 100) ||
					($word   =~ /^\d\d\d\d\d\d\d\d/ && $totalLeft == 94) 
				) {
					# say "entryNum  -> $entryNum";
					# say "totalLeft -> $totalLeft";
					# say "word      -> $word";
					if (
						($totalLeft > 94 && $totalLeft < 700) &&
						($word !~ /\d\d...2020/ && $word !~ /\d\d...2021/ && $word ne 'No' && $word ne 'O' && $word ne '1' && $word ne '2' && $word ne '3' && $word !~ /.*\d\d\/C$/ && $word !~ /.*\d\d\/\d.*$/)
					) {
						unless ($fromPage == $toPage) {
							unless ($pageNum == $fromPage) {
								next unless $hasStarted;
							}
							if ($word eq 'No.') {
								$hasStarted = 1;
							}
						}
						my $currentWord = lc $word;
						if ($currentWord eq $word) {
							if ($symptoms && $symptoms !~ /\/$/) {
								$symptoms .= ' ';
							}
						} else {
							if ($symptoms && $symptoms !~ /\/$/) {
								$symptoms .= ', ';
							}
						}
						$symptoms       .= $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif (looks_like_number $word && $totalLeft > 550 && $totalLeft < 850 && !$doseNumber) {
						die "[$pageNum] - [$word] - $totalLeft" unless looks_like_number $word;
						$doseNumber = $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif ($word =~ /.*\/.*/ && $totalLeft > 550 && $totalLeft < 850 && !$relativeDaysDuration) {
						$relativeDaysDuration = $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif (looks_like_number $word && $totalLeft > 550 && $totalLeft < 1350 && $doseNumber && !$toxicityGrade) {
						die "[$pageNum] - [$word] - $totalLeft" unless looks_like_number $word;
						$toxicityGrade = $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif (($word eq 'Yes' || $word eq 'No') && $totalLeft > 550 && $totalLeft < 1350 && $doseNumber && $toxicityGrade && !$vaxRelated) {
						$vaxRelated = $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif (($word eq 'R' || $word eq 'RS' || $word eq 'F' || $word eq 'RG' || $word eq 'N' || $word eq 'UNK') && $totalLeft > 1240 && $totalLeft < 2600 && !$outcome) {
						$outcome = $word;
						# say "$subjectNumber - $ageGroup - $trialSiteId - $subjectId - $systemOrganClass - $pageNum - $topMargin - $totalLeft - $entryNum - $word";
					} elsif (
						$word eq 'O'        || $word =~ /NA/              ||
						$word eq 'Y/N'      || $word eq 'Action:'         ||
						$word eq 'Cause'    || $word =~ /P\/TC/           ||
						$word eq 'C4591001' || $word eq 'Investigational' ||
						$word eq 'SAE/Imm'  || $word eq 'Onset'           ||
						$word eq 'Dur'      || $word eq 'Toxicity'        ||
						$word eq 'Vax'      || $word eq 'of'              ||
						$word eq 'Vaccine'  || $word eq 'Dose/'           ||
						$word eq 'Outcome'  || $word eq 'AE'              ||
						$word eq 'Date'     || $word eq 'Subject'         ||
						$word eq '(End'     || $word eq 'Date)'           ||
						$word eq '(Yes/No)'
					) {
						next;
					} elsif ($word =~ /\(.........\)/) {
						($outcomeDate) = $word =~ /\((.........)\)/
					} else {

					}
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'adverseEffects'}             = $symptoms;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'doseNumber'}           = $doseNumber;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'relativeDaysDuration'} = $relativeDaysDuration;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'vaxRelated'}           = $vaxRelated;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'outcome'}              = $outcome;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'outcomeDate'}          = $outcomeDate;
					$subjectAES{$subjectNumber}->{'adverseEffectsSets'}->{$adverseEffectSetNumber}->{'adverseEffects'}->{$adverseEffectNumber}->{'toxicityGrade'}        = $toxicityGrade;
				}
			}
		}
	}
}
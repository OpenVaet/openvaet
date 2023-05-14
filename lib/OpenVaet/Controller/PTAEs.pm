package OpenVaet::Controller::PTAEs;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use Scalar::Util qw(looks_like_number);
use FindBin;
use File::Path qw(make_path);
use lib "$FindBin::Bin/../lib";
use session;
use time;

my @adslColumns = qw(
  subjid
  usubjid
  age
  agetr01
  agegr1
  agegr1n
  race
  racen
  ethnic
  ethnicn
  arace
  aracen
  racegr1
  racegr1n
  sex
  sexn
  country
  saffl
  actarm
  actarmcd
  trtsdt
  vax101dt
  vax102dt
  vax201dt
  vax202dt
  vax10udt
  vax20udt
  reactofl
  phase
  phasen
  unblnddt
  bmicat
  bmicatn
  combodfl
  covblst
  hivfl
  x1csrdt
  saf1fl
  saf2fl
  aeRows
  aeserRows
  aeser
  aestdtc
  aestdy
  aescong
  aesdisab
  aesdth
  aeshosp
  aeslife
  aesmie
  aemeres
  aerel
  aereln
  astdt
  astdtf
  dthdt
  posPCR
  posNBinding
  covblstRecalc
  covblstRecalcSrc
  dayobsPiBnt
  dayobsPiPlacebo
  dayobsPiCrossov
  dayobsNpiBnt
  dayobsNpiPlacebo
  dayobsNpiCrossov
  earliestCovid
  earliestCovidVisit
);

my @adaeColumns = qw(
  aeser
  aestdtc
  aestdy
  aescong
  aesdisab
  aesdth
  aeshosp
  aeslife
  aesmie
  aemeres
  aerel
  aereln
  astdt
  astdtf
  aehlgt
  aehlt
);

sub pfizer_trial_after_effects {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub filter_data {
	my $self = shift;

	# Retrieves params from POST request.
	my $currentLanguage            = $self->param('currentLanguage')            // 'en';
	my $subjectsWithVoidCOVBLST    = $self->param('subjectsWithVoidCOVBLST')    // die;
	my $subjectsWithoutSAEs        = $self->param('subjectsWithoutSAEs')        // die;
	my $subjectsWithCentralPCR     = $self->param('subjectsWithCentralPCR')     // die;
	my $subjectsWithNBinding       = $self->param('subjectsWithNBinding')       // die;
	my $phase1IncludeBNT           = $self->param('phase1IncludeBNT')           // die;
	my $phase1IncludePlacebo       = $self->param('phase1IncludePlacebo')       // die;
	my $below16Include             = $self->param('below16Include')             // die;
	my $seniorsIncluded            = $self->param('seniorsIncluded')            // die;
	my $duplicatesInclude          = $self->param('duplicatesInclude')          // die;
	my $noCRFInclude               = $self->param('noCRFInclude')               // die;
	my $hivSubjectsIncluded        = $self->param('hivSubjectsIncluded')        // die;
	my $noSafetyPopFlagInclude     = $self->param('noSafetyPopFlagInclude')     // die;
	my $femaleIncluded             = $self->param('femaleIncluded')             // die;
	my $maleIncluded               = $self->param('maleIncluded')               // die;
	my $subjectToUnblinding        = $self->param('subjectToUnblinding')        // die;
	my $cutoffDate                 = $self->param('cutoffDate')                 // die;
	my $subjectsWithPriorInfect    = $self->param('subjectsWithPriorInfect')    // die;
	my $subjectsWithSymptoms       = $self->param('subjectsWithSymptoms')       // die;
	my $crossOverCountOnlyBNT      = $self->param('crossOverCountOnlyBNT')      // die;
	my $csvSeparator               = $self->param('csvSeparator')               // die;
	my $aeWithoutDate              = $self->param('aeWithoutDate')              // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;

	# Printing filtering statistics (required for the Filtering Logs).
	my @params = (
		$phase1IncludeBNT,
		$phase1IncludePlacebo,
		$below16Include,
		$subjectsWithNBinding,
		$subjectsWithCentralPCR,
		$subjectsWithSymptoms,
		$seniorsIncluded,
		$duplicatesInclude,
		$noCRFInclude,
		$crossOverCountOnlyBNT,
		$hivSubjectsIncluded,
		$noSafetyPopFlagInclude,
		$femaleIncluded,
		$maleIncluded,
		$subjectToUnblinding,
		$subjectsWithPriorInfect,
		$subjectsWithoutPriorInfect,
		$aeWithoutDate,
		$subjectsWithoutSAEs,
		$subjectsWithVoidCOVBLST
	);
	my @paramsLabels = (
		'phase1IncludeBNT',
		'phase1IncludePlacebo',
		'below16Include',
		'subjectsWithNBinding',
		'subjectsWithCentralPCR',
		'subjectsWithSymptoms',
		'seniorsIncluded',
		'duplicatesInclude',
		'noCRFInclude',
		'crossOverCountOnlyBNT',
		'hivSubjectsIncluded',
		'noSafetyPopFlagInclude',
		'femaleIncluded',
		'maleIncluded',
		'subjectToUnblinding',
		'subjectsWithPriorInfect',
		'subjectsWithoutPriorInfect',
		'aeWithoutDate',
		'subjectsWithoutSAEs',
		'subjectsWithVoidCOVBLST'
	);
	my $pNum = 0;
	my %params = ();
	my $path;
	for my $param (@params) {
		die unless $param eq 'true' || $param eq 'false';
		my $p = 'Y';
		$p = 'N' if $param eq 'false';
		$path .= "_$p" if $path;
		$path = "$p" if !$path;
		my $label = $paramsLabels[$pNum] // die;
		$params{$label} = $param;
		$pNum++;
	}
	$params{'cutoffDate'} = $cutoffDate;
	$params{'csvSeparator'} = $csvSeparator;
	$path .= "_$cutoffDate";
	make_path("public/pt_aes/$path") unless (-d "public/pt_aes/$path");
	open my $out1, '>:utf8', "public/pt_aes/$path/parameters.json" or die $!;
	print $out1 encode_json\%params;
	close $out1;

	my ($cutoffCompdate, $cutoffDatetime);
	if ($cutoffDate eq 'bla') {
		$cutoffCompdate = '20210313';
		$cutoffDatetime = '2021-03-13 12:00:00';
	} elsif ($cutoffDate eq 'end') {
		$cutoffCompdate = '20211231';
		$cutoffDatetime = '2021-12-31 12:00:00';
	} else {
		die;
	}

	# Configuring duplicates & patients without CRFs required.
	my %allDuplicates = ();
	my %duplicates = ();
	my %noCRFVaxData = ();
	$allDuplicates{'10561101'}  = 11331382;
	$allDuplicates{'11331382'}  = 10561101;
	$allDuplicates{'11101123'}  = 11331405;
	$allDuplicates{'11331405'}  = 11101123;
	$allDuplicates{'11491117'}  = 12691090;
	$allDuplicates{'12691090'}  = 11491117;
	$allDuplicates{'12691070'}  = 11351357;
	$allDuplicates{'11351357'}  = 12691070;
	$allDuplicates{'11341006'}  = 10891112;
	$allDuplicates{'10891112'}  = 11341006;
	$allDuplicates{'11231105'}  = 10711213;
	$allDuplicates{'10711213'}  = 11231105;
	$duplicates{'10561101'}  = 11331382;
	# $duplicates{'11331382'}  = 10561101;
	$duplicates{'11101123'}  = 11331405;
	# $duplicates{'11331405'}  = 11101123;
	$duplicates{'11491117'}  = 12691090;
	# $duplicates{'12691090'}  = 11491117;
	$duplicates{'12691070'}  = 11351357;
	# $duplicates{'11351357'}  = 12691070;
	$duplicates{'11341006'}  = 10891112;
	# $duplicates{'10891112'}  = 11341006;
	$duplicates{'11231105'}  = 10711213;
	# $duplicates{'10711213'}  = 11231105;
	$noCRFVaxData{'11631006'}   = 1;
	$noCRFVaxData{'11631005'}   = 1;
	$noCRFVaxData{'11631008'}   = 1;
	say "path : [$path]";
	say "phase1IncludeBNT : $phase1IncludeBNT";
	say "phase1IncludePlacebo : $phase1IncludePlacebo";
	say "below16Include : $below16Include";
	say "seniorsIncluded : $seniorsIncluded";
	say "duplicatesInclude : $duplicatesInclude";
	say "noCRFInclude : $noCRFInclude";
	say "hivSubjectsIncluded : $hivSubjectsIncluded";
	say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say "femaleIncluded : $femaleIncluded";
	say "maleIncluded : $maleIncluded";
	say "subjectToUnblinding : $subjectToUnblinding";
	say "subjectsWithNBinding : $subjectsWithNBinding";
	say "subjectsWithSymptoms : $subjectsWithSymptoms";
	say "subjectsWithCentralPCR : $subjectsWithCentralPCR";
	say "cutoffDate : $cutoffDate";
	say "crossOverCountOnlyBNT : $crossOverCountOnlyBNT";
	say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "subjectsWithVoidCOVBLST : $subjectsWithVoidCOVBLST";
	say "csvSeparator : $csvSeparator";

	# Loading subjects targeted.
	open my $in, '<:utf8', 'adverse_effects_raw_data.json';
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);

	my %tests = ();
	my %debug = ();

	# Parsing JSON input.
	my %json = %$json;
	my $filteringLogs = '';
	$filteringLogs .= "\n";
	my %filteringStats = ();
	my %filteredSubjects = ();
	my %filteredAEs = ();
	my %stats       = ();
	my %subjectsAEs = (); # Avoids to count duplictes on subjects AEs.
	open my $out5, '>:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.csv" or die $!;
	for my $adslColumn (@adslColumns) {
		print $out5 "$adslColumn$csvSeparator";
	}
	say $out5 '';
	open my $out6, '>:utf8', "public/pt_aes/$path/filtered_subjects_aes.csv" or die $!;
	print $out6 "subjid$csvSeparator";
	for my $adaeColumn (@adaeColumns) {
		print $out6 "$adaeColumn$csvSeparator";
	}
	say $out6 '';
	my %summaryStats = ();
	for my $subjectId (sort{$a <=> $b} keys %json) {
		$filteringStats{'totalSubjectsOverall'}++;

		# Preliminary filterings (excluding actarmcd = Screen failures & Not assigned)
		my $actarmcd = $json{$subjectId}->{'actarmcd'} // die;
		if ($actarmcd eq 'SCRNFAIL') {
			$filteringStats{'totalScreenFailures'}++;
			$filteringStats{'screenFailures'}->{$subjectId} = 1;
			next;
		}
		if ($actarmcd eq 'NOTASSGN') {
			$filteringStats{'totalNotAssigned'}++;
			$filteringStats{'notAssigned'}->{$subjectId} = 1;
			next;
		}
		if ($actarmcd eq 'NOTTRT') {
			$filteringStats{'totalNotTreated'}++;
			$filteringStats{'notTreated'}->{$subjectId} = 1;
			next;
		}

		my $categoArm = $actarmcd;
		if ($actarmcd ne 'PLACEBO') {
			$categoArm = 'BNT162b2 (30 mcg)';
		} else {
			$categoArm = 'Placebo';
		}
		$filteringStats{'totalSubjectsPreFilters'}->{'total'}++;
		$filteringStats{'totalSubjectsPreFilters'}->{'byArms'}->{$categoArm}++;

		# Filtering phase 1 subjects.
		if ($phase1IncludeBNT ne 'true') {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'Placebo') {
					$filteringStats{'totalPhase1BNT'}++;
					$filteringStats{'phase1BNT'}->{$subjectId} = 1;
					next;
				}
			}
		} else {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'Placebo' && $actArm ne 'BNT162b2 Phase 1 (30 mcg)') {
					$filteringStats{'totalPhase1BNTNotB2_30mcg'}++;
					$filteringStats{'phase1BNTNotB2_30mcg'}->{$subjectId} = 1;
					next;
				}
			}
		}

		# Filtering phase 1 placebo.
		if ($phase1IncludePlacebo ne 'true') {
			my $phase = $json{$subjectId}->{'phase'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless ($json{$subjectId}->{'adva.actarm'}) {
					die;
				}
				my $actArm = $json{$subjectId}->{'adva.actarm'} // die;
				if ($actArm ne 'BNT162b2 Phase 1 (30 mcg)') {
					$filteringStats{'totalPhase1Placebo'}++;
					$filteringStats{'phase1Placebo'}->{$subjectId} = 1;
					next;
				}
			}
		}

		# Filtering below 16.
		if ($below16Include ne 'true') {
			my $agetr01 = $json{$subjectId}->{'agetr01'} // die;
			if ($agetr01 < 16) {
				$filteringStats{'totalBelow16'}++;
				$filteringStats{'below16'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering above 54.
		if ($seniorsIncluded ne 'true') {
			my $agetr01 = $json{$subjectId}->{'agetr01'} // die;
			if ($agetr01 > 54) {
				$filteringStats{'totalAbove54'}++;
				$filteringStats{'above54'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering duplicates.
		if ($duplicatesInclude eq 'true') {
			if (exists $duplicates{$subjectId}) {
				$filteringStats{'totalDuplicates'}++;
				$filteringStats{'duplicates'}->{$subjectId} = 1;
				next;
			}
		} else {
			if (exists $allDuplicates{$subjectId}) {
				$filteringStats{'totalDuplicates'}++;
				$filteringStats{'duplicates'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering CRF Vax Data.
		if ($noCRFInclude ne 'true') {
			if (exists $noCRFVaxData{$subjectId}) {
				$filteringStats{'totalNoCRFVaxData'}++;
				$filteringStats{'noCRFVaxData'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering HIV
		if ($hivSubjectsIncluded ne 'true') {
			my $hivfl = $json{$subjectId}->{'hivfl'} // die;
			if ($hivfl ne 'N') {
				$filteringStats{'totalHIVFlags'}++;
				$filteringStats{'hivFlags'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Female.
		if ($femaleIncluded ne 'true') {
			my $sex = $json{$subjectId}->{'sex'} // die;
			if ($sex eq 'F') {
				$filteringStats{'totalFemales'}++;
				$filteringStats{'females'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Male.
		if ($maleIncluded ne 'true') {
			my $sex = $json{$subjectId}->{'sex'} // die;
			if ($sex eq 'M') {
				$filteringStats{'totalMales'}++;
				$filteringStats{'males'}->{$subjectId} = 1;
				next;
			}
		}

		# Filtering Safety Flag.
		if ($noSafetyPopFlagInclude ne 'true') {
			my $saffl = $json{$subjectId}->{'saffl'} // die;
			if ($saffl eq 'N') {
				$filteringStats{'totalExcludedFromSafety'}++;
				$filteringStats{'excludedFromSafety'}->{$subjectId} = 1;
				next;
			}
		}

		# Covid prior baseline.
		# next unless $json{$subjectId}->{'covblst'};
		if ($subjectsWithPriorInfect ne 'true') {
			my $covblst = $json{$subjectId}->{'covblst'} // die;
			if ($covblst ne 'NEG') {
				$filteringStats{'totalWithPriorInfection'}++;
				$filteringStats{'withPriorInfection'}->{$subjectId} = 1;
				next;
			}
		}

		# No covid prior baseline.
		if ($subjectsWithoutPriorInfect ne 'true') {
			my $covblst = $json{$subjectId}->{'covblst'} // die;
			if ($covblst ne 'POS') {
				$filteringStats{'totalWithoutPriorInfection'}++;
				$filteringStats{'withoutPriorInfection'}->{$subjectId} = 1;
				next;
			}
		}

		# No data in COVBLST tag
		if ($subjectsWithVoidCOVBLST ne 'true') {
			my $covblst = $json{$subjectId}->{'covblst'} // die;
			if (!$covblst) {
				$filteringStats{'totalWithoutCOVBLST'}++;
				$filteringStats{'withoutCOVBLST'}->{$subjectId} = 1;
				next;
			}
		}

		# Creating object, flushing deviations & default AES.
		$filteredSubjects{$subjectId} = \%{$json{$subjectId}};
		delete $filteredSubjects{$subjectId}->{'deviations'};


		# If the subject made it so far, integrating its data to the end data (stats, lin reg data).
		# Calculating total serious AE to cut-off or unblinding, depending on the constrain.
		my $aeserRows = 0;
		my $aeRows    = 0;
		my $aeserRowsPostDose3 = 0;
		my $aeRowsPostDose3    = 0;
		my $unblindingDatetime = $json{$subjectId}->{'unblnddt'} // die;
		my ($unblindingDate);
		if ($unblindingDatetime) {
			($unblindingDate) = split ' ', $unblindingDatetime;
			$unblindingDate =~ s/\D//g;
		}
		my %aesByDates  = ();
		my %saesByDates = ();

		# Filtering based on after effects settings.
		if (exists $json{$subjectId}->{'adaeRows'}) {
			for my $adaeRNum (sort{$a <=> $b} keys %{$json{$subjectId}->{'adaeRows'}}) {
				my $aeser  = $json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'aeser'}  // die;
				my $astdt  = $json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'astdt'}  // die;
				my $astdtf = $json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'astdtf'} // die;
				if ($aeWithoutDate ne 'true' && $astdtf && ($astdtf eq 'M' || $astdtf eq 'D')) {
					# p$json{$subjectId};
					$filteringStats{'totalAEsWithoutDate'}++;
					$filteringStats{'aesWithoutDate'}->{$subjectId}++;
					if ($aeser && $aeser eq 'Y') {
						$filteringStats{'totalSAEsWithoutDate'}++;
						$filteringStats{'saesWithoutDate'}->{$subjectId}++;
					}
					next;
				}
				my ($astcpdt);
				if ($astdt) {
					($astcpdt) = split ' ', $astdt;
					$astcpdt   =~ s/\D//g;
					die unless $astcpdt =~ /^........$/;
					if ($astcpdt > $cutoffCompdate) {
						$filteringStats{'totalAEsPostCutOff'}++;
						$filteringStats{'aesPostCutOff'}->{$subjectId}++;
						if ($aeser && $aeser eq 'Y') {
							$filteringStats{'totalSAEsPostCutOff'}++;
							$filteringStats{'saesPostCutOff'}->{$subjectId}++;
						}
						next;
					}
					if ($subjectToUnblinding eq 'true') {
						if ($unblindingDate && $astcpdt > $unblindingDate) {
							$filteringStats{'totalAEsPostUnblind'}++;
							$filteringStats{'aesPostUnblind'}->{$subjectId}++;
							if ($aeser && $aeser eq 'Y') {
								$filteringStats{'totalSAEsPostUnblind'}++;
								$filteringStats{'saesPostUnblind'}->{$subjectId}++;
							}
							next;
						}
					}
					$json{$subjectId}->{'adaeRows'}->{$adaeRNum}->{'astcpdt'} = $astcpdt;
				}

				# Incrementing AE & stats for sorting by earliest known date (or default to NA if only that)
				$astcpdt = '99999999' unless $astcpdt;
				if ($aeser && $aeser eq 'Y') {
					$aeserRows++;
					$saesByDates{$astcpdt}->{$adaeRNum} = \%{$json{$subjectId}->{'adaeRows'}->{$adaeRNum}};
				}
				$aesByDates{$astcpdt}->{$adaeRNum} = \%{$json{$subjectId}->{'adaeRows'}->{$adaeRNum}};
				$aeRows++;
			}
		}

		# Incrementing post AE parsing stats.
		$filteredSubjects{$subjectId}->{'aeRows'} = $aeRows;
		$filteredSubjects{$subjectId}->{'aeserRows'} = $aeserRows;
		if ($aeserRows) {
			die unless keys %saesByDates;
			for my $dt (sort{$a <=> $b} keys %saesByDates) {
				for my $adaeRNum (sort{$a <=> $b} keys %{$saesByDates{$dt}}) {
					for my $adaeColumn (@adaeColumns) {
						my $value = $saesByDates{$dt}->{$adaeRNum}->{$adaeColumn} // die "adaeColumn : $adaeColumn";
						if (
							!exists $filteredSubjects{$subjectId}->{$adaeColumn} ||
							(
								exists $filteredSubjects{$subjectId}->{$adaeColumn} &&
								$filteredSubjects{$subjectId}->{$adaeColumn} ne 'Y' && $value eq 'Y'
							)
						) {
							$filteredSubjects{$subjectId}->{$adaeColumn} = $value;
						}
					}
				}
				last;
			}
		} else {
			if ($subjectsWithoutSAEs ne "true") {
				delete $filteredSubjects{$subjectId};
				$filteringStats{'totalWithoutSAEs'}++;
				$filteringStats{'withoutSAEs'}->{$subjectId} = 1;
				next;
			}
		}

		# Increments global stats
		$filteringStats{'totalSubjectsPostFilter'}->{'total'}++;
		$filteringStats{'totalSubjectsPostFilter'}->{'byArms'}->{$categoArm}++;

		# Loading subject's tests.
		# p$filteredSubjects{$subjectId};
		# last if $filteringStats{'totalSubjectsPostFilter'}->{'total'} > 10;
		my $limitDate    = $cutoffCompdate;
		my $limitDateh   = $cutoffDatetime;
		if ($subjectToUnblinding eq 'true') {
			$limitDate   = $unblindingDate;
			$limitDateh  = $unblindingDatetime;
			unless ($limitDate) {
				$limitDate  = $cutoffCompdate;
				$limitDateh = $cutoffDatetime;
			}
		}
		my $posPCR       = subject_central_pcrs_by_visits($subjectId, $limitDate, %{$json{$subjectId}});
		my $posNBinding  = subject_central_nbindings_by_visits($subjectId, $limitDate, %{$json{$subjectId}});
		my $nBindingV1   = $filteredSubjects{$subjectId}->{'nBindings'}->{'V1_DAY1_VAX1_L'}->{'avalc'} // 'MIS';
		my $centralPcrV1 = $filteredSubjects{$subjectId}->{'pcrs'}->{'V1_DAY1_VAX1_L'}->{'mborres'}    // 'MIS';

		# Testing for errors in the population regarding unknown tests (none, doesn't affect totals).
		# next if $nBindingV1 eq 'MIS' || $centralPcrV1 eq 'MIS' || $centralPcrV1 eq 'IND';
		$tests{'nBinding'}->{$nBindingV1}++;
		$tests{'pcr'}->{$centralPcrV1}++;

		# Setting Covid at baseline own tags.
		my $covblst = $json{$subjectId}->{'covblst'} // die;
		my $actarm  = $json{$subjectId}->{'actarm'}  // die;
		my ($covblstRecalc, $covblstRecalcSrc) = (0, undef);
		if ($nBindingV1 eq 'POS' || $centralPcrV1 eq 'POS') {
			$covblstRecalc = 1;
			if ($nBindingV1 eq 'POS' && $centralPcrV1 eq 'POS') {
				$covblstRecalcSrc = 'Pcr + N-Binding';
			} else {
				$covblstRecalcSrc = 'N-Binding' if $nBindingV1   eq 'POS';
				$covblstRecalcSrc = 'Pcr'       if $centralPcrV1 eq 'POS';
			}
		}
		if ($covblst eq 'POS') {
			# Setting Covid at baseline tag if unset so far.
			unless ($covblstRecalc) {
				$covblstRecalc = 1;
				$covblstRecalcSrc = 'Baseline tag';
			}
		}
		$filteredSubjects{$subjectId}->{'posPCR'}           = $posPCR;
		$filteredSubjects{$subjectId}->{'posNBinding'}      = $posNBinding;
		$filteredSubjects{$subjectId}->{'covblstRecalc'}    = $covblstRecalc;
		$filteredSubjects{$subjectId}->{'covblstRecalcSrc'} = $covblstRecalcSrc;

		# Organizing doses received in a hashtable allowing easy numerical sorting.
		my $vax101dt     = $json{$subjectId}->{'vax101dt'} // die;
		my $vax102dt     = $json{$subjectId}->{'vax102dt'} // die;
		my $vax201dt     = $json{$subjectId}->{'vax201dt'} // die;
		if ($vax201dt && $unblindingDate) {
			my ($vax201cp) = split ' ', $vax201dt;
			$vax201cp =~ s/\D//g;
			if ($vax201cp < $unblindingDate) {
				die "indeed";
				my $daysBetween = time::calculate_days_difference($unblindingDatetime, $vax201dt);
				say "$subjectId - $unblindingDatetime | $vax201dt - $vax201cp > $unblindingDate";
				$debug{'byDays'}->{$daysBetween}->{'total'}++;
				$debug{'total'}++;
			}
		}
		my $vax202dt     = $json{$subjectId}->{'vax202dt'} // die;
		my $dthdt        = $json{$subjectId}->{'dthdt'}    // die;
		my $deathcptdt;
		if ($dthdt) {
			($deathcptdt) = split ' ', $dthdt;
			$deathcptdt   =~ s/\D//g;
		}
		my %doseDates    = ();
		$doseDates{'1'}  = $vax101dt;
		die unless $vax101dt;
		$doseDates{'2'}  = $vax102dt if $vax102dt;
		$doseDates{'3'}  = $vax201dt if $vax201dt;
		$doseDates{'4'}  = $vax202dt if $vax202dt;

		# If the subject had Covid at baseline he will be accruing time only for the "infected prior dose" group.
		my
		(
			$dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov,
			$dayobsNpiBnt, $dayobsNpiPlacebo, $dayobsNpiCrossov
		) = (
			0, 0, 0, 0, 0, 0
		);
		if ($covblstRecalc) {
			# Setting values related to subject's populations.
			(my $groupArm, $dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov) = time_of_exposure_from_simple($actarm, $vax101dt, $vax102dt, $vax201dt, $dthdt, $deathcptdt, $limitDateh, $limitDate);

			# Once done with all the required filterings, incrementing stats.
			# Population stats.
			# Total Subjects
			$stats{'Doses_With_Infection'}->{'totalSubjects'}++;
			# Subject's Arm.
			$stats{'Doses_With_Infection'}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
			if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
				$stats{'Doses_With_Infection'}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
			}
			# Days of exposure for each arm.
			$stats{'Doses_With_Infection'}->{'dayobsCrossov'} += $dayobsPiCrossov;
			$stats{'Doses_With_Infection'}->{'dayobsBnt'}     += $dayobsPiBnt;
			$stats{'Doses_With_Infection'}->{'dayobsPlacebo'} += $dayobsPiPlacebo;

			# AE stats.
			my ($hasAE, $hasSAE) = (0, 0);
			if (keys %aesByDates) {
				# p%aesByDates;
				# last;
				# For each date on which AEs have been reported
				for my $aeCompdate (sort{$a <=> $b} keys %aesByDates) {
					my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
					next unless ($aeY && $aeM && $aeD);
					# Skipping AE if observed after cut-off.
					next if $aeCompdate > $limitDate;
					my %doseDatesByDates = ();
					for my $dNum (sort{$a <=> $b} keys %doseDates) {
						my $dt = $doseDates{$dNum} // die;
						my ($cpDt) = split ' ', $dNum;
						$cpDt =~ s/\D//g;
						next unless $cpDt < $aeCompdate;
						my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
						$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
						$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
					}
					my ($closestDoseDate, $closestDose, $doseToAEDays);
					for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
						$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
						$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
						$doseToAEDays    = $daysBetween;
						last;
					}
					my ($closestDoseCompdate) = split ' ', $closestDoseDate;
					$closestDoseCompdate =~ s/\D//g;
					my $doseArm = $categoArm;
					if ($closestDose > 2) {
						$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
					}
					if ($crossOverCountOnlyBNT eq 'true' && $vax201dt) {
						next if $closestDose < 3;
					}
					# say "*" x 50;
					# say "aeCompdate               : $aeCompdate";
					# say "closestDoseDate          : $closestDoseDate";
					# say "closestDose              : $closestDose";
					# say "doseToAEDays             : $doseToAEDays";
					# say "doseArm                  : $doseArm";

					# For Each adverse effect reported on this date.
					for my $aeObserved (sort keys %{$aesByDates{$aeCompdate}}) {
						# p$aesByDates{$aeCompdate}->{$aeObserved};die;
						my $aehlgt        = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
						# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
						my $aehlt         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
						my $aeser         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
						my $toxicityGrade = $aesByDates{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
						if ($aeser eq 'Y') {
							$aeser  = 1;
							$hasSAE = 1;
							$aeserRowsPostDose3++ if $closestDose > 2;
						} elsif ($aeser eq 'N') {
							$aeser = 0;
						} else {
							$aeser = 0;
						}
						$aeRowsPostDose3++    if $closestDose > 2;
						$hasAE = 1;
						# say "*" x 50;
						# say "aehlgt                   : $aehlgt";
						# say "aehlt                    : $aehlt";
						# say "aeser                    : $aeser";
						# say "toxicityGrade            : $toxicityGrade";
						# die;

						# Grade level - global stat & by toxicity stats.
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalEvents'}++;
						if ($aeser) {
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalEvents'}++;
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
						}

						# Category level - stats & by toxicity stats
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
						if ($aeser) {
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
						}

						# Reaction level - stats & by toxicity stats. 
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
						}
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
						$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
						if ($aeser) {
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
							$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses_With_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
								$stats{'Doses_With_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
							}
						}
					}
				}
			}
			# Total subjects with AE.
			if ($hasAE) {
				$stats{'Doses_With_Infection'}->{'aes'}->{'totalSubjects'}++;
			}
			# Total subjects with SAE.
			if ($hasSAE) {
				$stats{'Doses_With_Infection'}->{'saes'}->{'totalSubjects'}++;
			}
		} else {
			# If not he will be accruing time of exposure for the "non infected group"
			# up to his infection if it occures before dose 2, 3 or 4
			my $hasInfection  = 0;
			my $subjectsWithCentralPCR = $self->param('subjectsWithCentralPCR') // die;
			my $subjectsWithNBinding = $self->param('subjectsWithNBinding') // die;
			if ($subjectsWithSymptoms eq 'true') {
				my $hasSymptoms = subject_symptoms_by_visits($subjectId, $limitDate, %{$json{$subjectId}});
				if ($posPCR || $hasSymptoms || $posNBinding) {
					$hasInfection = 1;
				}
			} elsif ($subjectsWithCentralPCR eq 'true' && $subjectsWithNBinding eq 'true') {
				if ($posPCR || $posNBinding) {
					$hasInfection = 1;
				}
			} elsif ($subjectsWithCentralPCR eq 'true' || $subjectsWithNBinding eq 'true') {
				if (($posPCR && $subjectsWithCentralPCR eq 'true') || ($posNBinding && $subjectsWithNBinding eq 'true')) {
					$hasInfection = 1;
				}
			}
			if ($hasInfection) {
				my $earliestCovid = 99999999;
				my $earliestVisit;
				# p$json{$subjectId}->{'pcrs'};
				if ($subjectsWithSymptoms eq 'true') {
					for my $visit (sort keys %{$json{$subjectId}->{'symptoms'}}) {
						my $symptomCompdate = $json{$subjectId}->{'symptoms'}->{$visit}->{'symptomCompdate'} // die;

						# Skips the visit unless it fits with the phase 3.
						next unless $symptomCompdate >= 20200720;
						next unless $symptomCompdate <= $cutoffCompdate;
						die unless keys %{$json{$subjectId}->{'symptoms'}->{$visit}->{'symptoms'}};
						if ($symptomCompdate < $earliestCovid) {
							$earliestCovid = $symptomCompdate;
							$earliestVisit = $visit;
						}
					}
				}
				if ($subjectsWithCentralPCR eq 'true') {
					for my $visit (sort keys %{$json{$subjectId}->{'pcrs'}}) {
						my $visitcpdt = $json{$subjectId}->{'pcrs'}->{$visit}->{'visitcpdt'} // next;
						my $mborres   = $json{$subjectId}->{'pcrs'}->{$visit}->{'mborres'}   // die;
						if ($mborres eq 'POS') {
							if ($visitcpdt < $earliestCovid) {
								$earliestCovid = $visitcpdt;
								$earliestVisit = $visit;
							}
						}
					}
				}
				if ($subjectsWithNBinding eq 'true') {
					for my $visit (sort keys %{$json{$subjectId}->{'nBindings'}}) {
						my $visitcpdt = $json{$subjectId}->{'nBindings'}->{$visit}->{'visitcpdt'} // next;
						my $avalc     = $json{$subjectId}->{'nBindings'}->{$visit}->{'avalc'}     // die;
						if ($avalc eq 'POS') {
							if ($visitcpdt < $earliestCovid) {
								$earliestCovid = $visitcpdt;
								$earliestVisit = $visit;
							}
						}
					}
				}
				die if $earliestCovid eq 99999999;
				$filteredSubjects{$subjectId}->{'earliestCovid'} = $earliestCovid;
				$filteredSubjects{$subjectId}->{'earliestCovidVisit'} = $earliestVisit;
				my $latestDoseDatetime;
				for my $doseNum (sort{$b <=> $a} keys %doseDates) {
					$latestDoseDatetime = $doseDates{$doseNum} // die;
					last;
				}
				my ($latestDoseDate) = split ' ', $latestDoseDatetime;
				$latestDoseDate =~ s/\D//g;

				if ($earliestCovid < $latestDoseDate) {
					# COVID prior last dose, so the subject will accrue time in both groups.
					# say '';
					# say "*" x 50;
					# say "*" x 50;
					# say "subjectId                : $subjectId";
					# say "trialSiteId              : $trialSiteId";
					# say "arm                      : $arm";
					# say "randomizationDatetime    : $randomizationDatetime";
					# say "covidAtBaseline          : $covidAtBaseline";
					# say "dose1Datetime            : $dose1Datetime";
					# say "dose2Datetime            : $dose2Datetime";
					# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
					# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
					# say "centralNAATV1            : [$centralNAATV1]";
					# say "local                    :";
					# p%localPCRsByVisits;
					# say "central                  :";
					# p%centralPCRsByVisits;
					# say "symptoms                 :";
					# p%symptomsByVisit;
					# say "limitDate                : $limitDate";
					# say "posNBinding              : $posNBinding";
					# say "posPCR    : $posPCR";
					# say "earliestCovid            : $earliestCovid";
					# say "earliestVisit            : $earliestVisit";
					# say "latestDoseDatetime       : $latestDoseDatetime";
					# say "latestDoseDate           : $latestDoseDate";
					my $lastDosePriorCovidDate = 99999999;
					my $lastDosePriorCovid;
					for my $doseNum (sort{$b <=> $a} keys %doseDates) {
						my $doseDatetime = $doseDates{$doseNum} // die;
						my ($latestDoseDate) = split ' ', $doseDatetime;
						$latestDoseDate =~ s/\D//g;
						$lastDosePriorCovidDate = $latestDoseDate;
						$lastDosePriorCovid = $doseNum;
						last if $latestDoseDate < $earliestCovid;
					}
					die unless $lastDosePriorCovid;
					my ($lDY, $lDM, $lDD) = $lastDosePriorCovidDate =~ /(....)(..)(..)/;
					my $lastDosePriorCovidDatetime = "$lDY-$lDM-$lDD 12:00:00";
					# say "lastDosePriorCovidDate   : $lastDosePriorCovidDate";
					# say "lastDosePriorCovid       : $lastDosePriorCovid";

					# From first dose, to dose post infection, subject counts as "without infection".
					# Then he counts as "post infection".
					my @labels = ('Doses_Without_Infection', 'Doses_With_Infection');
					for my $label (@labels) {
						# Normal scenario - Covid post exposure.
						# Setting values related to subject's populations.
						my ($groupArm, $treatmentCutoffCompdate);
						if ($label eq 'Doses_Without_Infection') {
							($groupArm, $dayobsNpiBnt, $dayobsNpiPlacebo, $dayobsNpiCrossov, $treatmentCutoffCompdate) = time_of_exposure_from_conflicting($label, $actarm, $vax101dt, $vax102dt, $vax201dt, $vax202dt, $dthdt, $deathcptdt, $limitDateh, $limitDate, $earliestCovid, $lastDosePriorCovid, $lastDosePriorCovidDate);
							# Days of exposure for each arm.
							die unless $dayobsNpiBnt || $dayobsNpiPlacebo || $dayobsNpiCrossov;
							$stats{$label}->{'dayobsCrossov'} += $dayobsNpiCrossov;
							$stats{$label}->{'dayobsBnt'}     += $dayobsNpiBnt;
							$stats{$label}->{'dayobsPlacebo'} += $dayobsNpiPlacebo;
						} else {
							($groupArm, $dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov, $treatmentCutoffCompdate) = time_of_exposure_from_conflicting($label, $actarm, $vax101dt, $vax102dt, $vax201dt, $vax202dt, $dthdt, $deathcptdt, $limitDateh, $limitDate, $earliestCovid, $lastDosePriorCovid, $lastDosePriorCovidDate);
							# Days of exposure for each arm.
							die unless $dayobsPiCrossov || $dayobsPiBnt || $dayobsPiPlacebo;
							$stats{$label}->{'dayobsCrossov'} += $dayobsPiCrossov;
							$stats{$label}->{'dayobsBnt'}     += $dayobsPiBnt;
							$stats{$label}->{'dayobsPlacebo'} += $dayobsPiPlacebo;
						}
						# say '';
						# say "*" x 50;
						# say "*" x 50;
						# say "subjectId                : $subjectId";
						# say "trialSiteId              : $trialSiteId";
						# say "arm                      : $arm";
						# say "randomizationDatetime    : $randomizationDatetime";
						# say "covidAtBaseline          : $covidAtBaseline";
						# say "dose1Datetime            : $dose1Datetime";
						# say "dose2Datetime            : $dose2Datetime";
						# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
						# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
						# say "centralNAATV1            : [$centralNAATV1]";
						# say "local                    :";
						# p%localPCRsByVisits;
						# say "central                  :";
						# p%centralPCRsByVisits;
						# say "symptoms                 :";
						# p%symptomsByVisit;
						# say "limitDate                : $limitDate";
						# say "dayobsNpiBnt              : $dayobsNpiBnt";
						# say "dayobsPlacebo               : $dayobsPlacebo";
						# say "dayobsCrossov     : $dayobsCrossov";
						# say "$groupArm, $dayobsNpiBnt, $dayobsPlacebo, $dayobsCrossov, $treatmentCutoffCompdate";

						# Once done with all the required filterings, incrementing stats.
						# Population stats.
						# Total Subjects
						$stats{$label}->{'totalSubjects'}++;
						# Subject's Arm.
						$stats{$label}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
						if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
							$stats{$label}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
						}

						# AE stats.
						my ($hasAE, $hasSAE) = (0, 0);
						if (keys %aesByDates) {
							# For each date on which AEs have been reported
							for my $aeCompdate (sort{$a <=> $b} keys %aesByDates) {
								my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
								next unless ($aeY && $aeM && $aeD);
								# Skipping AE if observed after cut-off.
								next if $aeCompdate > $treatmentCutoffCompdate;
								my %doseDatesByDates = ();
								for my $dNum (sort{$a <=> $b} keys %doseDates) {
									my $dt = $doseDates{$dNum} // die;
									my ($cpDt) = split ' ', $dNum;
									$cpDt =~ s/\D//g;
									next unless $cpDt < $aeCompdate;
									my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
									$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
									$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
								}
								my ($closestDoseDate, $closestDose, $doseToAEDays);
								for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
									$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
									$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
									$doseToAEDays    = $daysBetween;
									last;
								}

								# Filtering AE based on label & closest dose.
								if ($label eq 'Doses_With_Infection') {
									next if $closestDose <= $lastDosePriorCovid;
									# say "closestDose        : $closestDose";
									# say "lastDosePriorCovid : $lastDosePriorCovid";
									# die;
								} elsif ($label eq 'Doses_Without_Infection') {
									next if $closestDose > $lastDosePriorCovid;
									# say "closestDose        : $closestDose";
									# say "lastDosePriorCovid : $lastDosePriorCovid";
									# die;
								} else {
									# say "closestDose        : $closestDose";
									# say "lastDosePriorCovid : $lastDosePriorCovid";
									# die;
								}
								my ($closestDoseCompdate) = split ' ', $closestDoseDate;
								$closestDoseCompdate =~ s/\D//g;
								my $doseArm = $categoArm;
								if ($categoArm ne 'Placebo') {
									$doseArm = 'BNT162b2 (30 mcg)';
								}
								if ($closestDose > 2) {
									$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
								}
								if ($crossOverCountOnlyBNT eq 'true' && $vax201dt) {
									next if $closestDose < 3;
								}
								# say "*" x 50;
								# say "aeCompdate               : $aeCompdate";
								# say "closestDoseDate          : $closestDoseDate";
								# say "closestDose              : $closestDose";
								# say "doseToAEDays             : $doseToAEDays";
								# say "doseArm                  : $doseArm";

								# For Each adverse effect reported on this date.
								for my $aeObserved (sort keys %{$aesByDates{$aeCompdate}}) {
									# p$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved};die;
									my $aehlgt        = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
									# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
									my $aehlt         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
									my $aeser         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
									my $toxicityGrade = $aesByDates{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
									if ($aeser eq 'Y') {
										$aeser  = 1;
										$hasSAE = 1;
										$aeserRowsPostDose3++ if $closestDose > 2;
									} elsif ($aeser eq 'N') {
										$aeser = 0;
									} else {
										$aeser = 0;
									}
									$aeRowsPostDose3++    if $closestDose > 2;
									$hasAE = 1;
									# say "*" x 50;
									# say "aehlgt                   : $aehlgt";
									# say "aehlt                    : $aehlt";
									# say "aeser                    : $aeser";
									# say "toxicityGrade            : $toxicityGrade";
									# die;

									# Grade level - global stat & by toxicity stats.
									unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalEvents'}++;
									if ($aeser) {
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalEvents'}++;
										unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
										unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
									}

									# Category level - stats & by toxicity stats
									unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
									if ($aeser) {
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
										unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
										unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
									}

									# Reaction level - stats & by toxicity stats. 
									unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
										$subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
									}
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
									$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
									if ($aeser) {
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
										$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
										unless (exists $subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
										unless (exists $subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
											$subjectsAEs{$label}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
											$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
										}
									}
								}
							}
						}
						# Total subjects with AE.
						if ($hasAE) {
							$stats{$label}->{'aes'}->{'totalSubjects'}++;
						}
						# Total subjects with SAE.
						if ($hasSAE) {
							$stats{$label}->{'saes'}->{'totalSubjects'}++;
						}
						if ($label eq 'Doses_Without_Infection') {
						} else {

						}
					}
					# p%doseDates;
					# die;
				} else {
					# Normal scenario - Covid post exposure.
					# Setting values related to subject's populations.
					(my $groupArm, $dayobsNpiBnt, $dayobsNpiPlacebo, $dayobsNpiCrossov) = time_of_exposure_from_simple($actarm, $vax101dt, $vax102dt, $vax201dt, $dthdt, $deathcptdt, $limitDateh, $limitDate);
					# say '';
					# say "*" x 50;
					# say "*" x 50;
					# say "subjectId                : $subjectId";
					# say "trialSiteId              : $trialSiteId";
					# say "actarm                      : $actarm";
					# say "randomizationDatetime    : $randomizationDatetime";
					# say "covidAtBaseline          : $covidAtBaseline";
					# say "dose1Datetime            : $dose1Datetime";
					# say "dose2Datetime            : $dose2Datetime";
					# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
					# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
					# say "centralNAATV1            : [$centralNAATV1]";
					# say "local                    :";
					# p%localPCRsByVisits;
					# say "central                  :";
					# p%centralPCRsByVisits;
					# say "symptoms                 :";
					# p%symptomsByVisit;
					# say "limitDate                : $limitDate";
					# say "dayobsBnt              : $dayobsBnt";
					# say "dayobsPlacebo               : $dayobsPlacebo";
					# say "dayobsCrossov     : $dayobsCrossov";

					# Once done with all the required filterings, incrementing stats.
					# Population stats.
					# Total Subjects
					$stats{'Doses_Without_Infection'}->{'aes'}->{'totalSubjects'}++;
					# Subject's Arm.
					$stats{'Doses_Without_Infection'}->{'byArms'}->{$groupArm}->{'aes'}->{'totalSubjects'}++;
					if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched actarms, also counts as BNT subject.
						$stats{'Doses_Without_Infection'}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalSubjects'}++;
					}
					# Days of exposure for each actarm.
					$stats{'Doses_Without_Infection'}->{'dayobsCrossov'} += $dayobsNpiCrossov;
					$stats{'Doses_Without_Infection'}->{'dayobsBnt'}     += $dayobsNpiBnt;
					$stats{'Doses_Without_Infection'}->{'dayobsPlacebo'} += $dayobsNpiPlacebo;

					# AE stats.
					my ($hasAE, $hasSAE) = (0, 0);
					if (keys %aesByDates) {
						# For each date on which AEs have been reported
						for my $aeCompdate (sort{$a <=> $b} keys %aesByDates) {
							my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
							next unless ($aeY && $aeM && $aeD);
							# Skipping AE if observed after cut-off.
							next if $aeCompdate > $limitDate;
							my %doseDatesByDates = ();
							for my $dNum (sort{$a <=> $b} keys %doseDates) {
								my $dt = $doseDates{$dNum} // die;
								my ($cpDt) = split ' ', $dNum;
								$cpDt =~ s/\D//g;
								next unless $cpDt < $aeCompdate;
								my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
								$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
								$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
							}
							my ($closestDoseDate, $closestDose, $doseToAEDays);
							for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
								$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
								$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
								$doseToAEDays    = $daysBetween;
								last;
							}
							my ($closestDoseCompdate) = split ' ', $closestDoseDate;
							$closestDoseCompdate =~ s/\D//g;
							my $doseArm = $actarm;
							if ($actarm ne 'Placebo') {
								$doseArm = 'BNT162b2 (30 mcg)';
							}
							if ($closestDose > 2) {
								$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
							}
							if ($crossOverCountOnlyBNT eq 'true' && $vax201dt) {
								next if $closestDose < 3;
							}
							# say "*" x 50;
							# say "aeCompdate               : $aeCompdate";
							# say "closestDoseDate          : $closestDoseDate";
							# say "closestDose              : $closestDose";
							# say "doseToAEDays             : $doseToAEDays";
							# say "doseArm                  : $doseArm";

							# For Each adverse effect reported on this date.
							for my $aeObserved (sort keys %{$aesByDates{$aeCompdate}}) {
								# p$aesByDates{$aeCompdate}->{$aeObserved};die;
								my $aehlgt        = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
								# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
								my $aehlt         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
								my $aeser         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
								my $toxicityGrade = $aesByDates{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
								if ($aeser eq 'Y') {
									$aeser  = 1;
									$hasSAE = 1;
									$aeserRowsPostDose3++ if $closestDose > 2;
								} elsif ($aeser eq 'N') {
									$aeser = 0;
								} else {
									$aeser = 0;
								}
								$aeRowsPostDose3++    if $closestDose > 2;
								$hasAE = 1;
								# say "*" x 50;
								# say "aehlgt                   : $aehlgt";
								# say "aehlt                    : $aehlt";
								# say "aeser                    : $aeser";
								# say "toxicityGrade            : $toxicityGrade";
								# die;

								# Grade level - global stat & by toxicity stats.
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalEvents'}++;
								if ($aeser) {
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalEvents'}++;
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
								}

								# Category level - stats & by toxicity stats
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
								if ($aeser) {
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
								}

								# Reaction level - stats & by toxicity stats. 
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
								}
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
								if ($aeser) {
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
									unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
										$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
									}
								}
							}
						}
					}
					# Total subjects with AE.
					if ($hasAE) {
						$stats{'Doses_Without_Infection'}->{'aes'}->{'totalSubjects'}++;
					}
					# Total subjects with SAE.
					if ($hasSAE) {
						$stats{'Doses_Without_Infection'}->{'saes'}->{'totalSubjects'}++;
					}
				}
			} else {

				# Setting values related to subject's populations.
				(my $groupArm, $dayobsNpiBnt, $dayobsNpiPlacebo, $dayobsNpiCrossov) = time_of_exposure_from_simple($actarm, $vax101dt, $vax102dt, $vax201dt, $dthdt, $deathcptdt, $limitDateh, $limitDate);
				# say '';
				# say "*" x 50;
				# say "*" x 50;
				# say "subjectId                : $subjectId";
				# say "trialSiteId              : $trialSiteId";
				# say "arm                      : $arm";
				# say "randomizationDatetime    : $randomizationDatetime";
				# say "covidAtBaseline          : $covidAtBaseline";
				# say "dose1Datetime            : $dose1Datetime";
				# say "dose2Datetime            : $dose2Datetime";
				# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
				# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
				# say "centralNAATV1            : [$centralNAATV1]";
				# say "local                    :";
				# p%localPCRsByVisits;
				# say "central                  :";
				# p%centralPCRsByVisits;
				# say "symptoms                 :";
				# p%symptomsByVisit;
				# say "limitDate                : $limitDate";
				# say "dayobsBnt              : $dayobsBnt";
				# say "dayobsPlacebo               : $dayobsPlacebo";
				# say "dayobsCrossov     : $dayobsCrossov";

				# Once done with all the required filterings, incrementing stats.
				# Population stats.
				# Total Subjects
				$stats{'Doses_Without_Infection'}->{'totalSubjects'}++;
				# Subject's Arm.
				$stats{'Doses_Without_Infection'}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
				if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
					$stats{'Doses_Without_Infection'}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
				}
				# Days of exposure for each arm.
				$stats{'Doses_Without_Infection'}->{'dayobsCrossov'} += $dayobsNpiCrossov;
				$stats{'Doses_Without_Infection'}->{'dayobsBnt'}     += $dayobsNpiBnt;
				$stats{'Doses_Without_Infection'}->{'dayobsPlacebo'} += $dayobsNpiPlacebo;
				# AE stats.
				my ($hasAE, $hasSAE) = (0, 0);
				if (keys %aesByDates) {
					# For each date on which AEs have been reported
					for my $aeCompdate (sort{$a <=> $b} keys %aesByDates) {
						my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
						next unless ($aeY && $aeM && $aeD);
						# Skipping AE if observed after cut-off.
						next if $aeCompdate > $limitDate;
						my %doseDatesByDates = ();
						for my $dNum (sort{$a <=> $b} keys %doseDates) {
							my $dt = $doseDates{$dNum} // die;
							my ($cpDt) = split ' ', $dNum;
							$cpDt =~ s/\D//g;
							next unless $cpDt < $aeCompdate;
							my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
							$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
							$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
						}
						my ($closestDoseDate, $closestDose, $doseToAEDays);
						for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
							$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
							$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
							$doseToAEDays    = $daysBetween;
							last;
						}
						my ($closestDoseCompdate) = split ' ', $closestDoseDate;
						$closestDoseCompdate =~ s/\D//g;
						my $doseArm = $categoArm;
						if ($closestDose > 2) {
							$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
						}
						if ($crossOverCountOnlyBNT eq 'true' && $vax201dt) {
							next if $closestDose < 3;
						}
						# say "*" x 50;
						# say "aeCompdate               : $aeCompdate";
						# say "closestDoseDate          : $closestDoseDate";
						# say "closestDose              : $closestDose";
						# say "doseToAEDays             : $doseToAEDays";
						# say "doseArm                  : $doseArm";

						# For Each adverse effect reported on this date.
						for my $aeObserved (sort keys %{$aesByDates{$aeCompdate}}) {
							my $aehlgt        = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
							my $aehlt         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
							my $aeser         = $aesByDates{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
							my $toxicityGrade = $aesByDates{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
							if ($aeser eq 'Y') {
								$aeser  = 1;
								$hasSAE = 1;
								$aeserRowsPostDose3++ if $closestDose > 2;
							} elsif ($aeser eq 'N') {
								$aeser = 0;
							} else {
								$aeser = 0;
							}
							$aeRowsPostDose3++    if $closestDose > 2;
							$hasAE = 1;
							# say "*" x 50;
							# say "aehlgt                   : $aehlgt";
							# say "aehlt                    : $aehlt";
							# say "aeser                    : $aeser";
							# say "toxicityGrade            : $toxicityGrade";
							# die;

							# Grade level - global stat & by toxicity stats.
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'aes'}->{'totalEvents'}++;
							if ($aeser) {
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalEvents'}++;
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
							}

							# Category level - stats & by toxicity stats
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'}++;
							if ($aeser) {
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'}++;
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
							}

							# Reaction level - stats & by toxicity stats. 
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalSubjects'}++;
							}
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'aes'}->{'totalEvents'}++;
							$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'}++;
							if ($aeser) {
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalEvents'}++;
								$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'}++;
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{'All_Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses_Without_Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'}++;
									$stats{'Doses_Without_Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'saes'}->{'totalSubjects'}++;
								}
							}
						}
					}
				}
				# Total subjects with AE.
				if ($hasAE) {
					$stats{'Doses_Without_Infection'}->{'aes'}->{'totalSubjects'}++;
				}
				# Total subjects with SAE.
				if ($hasSAE) {
					$stats{'Doses_Without_Infection'}->{'saes'}->{'totalSubjects'}++;
				}
			}
		}
		die if !$dayobsPiBnt && !$dayobsPiPlacebo && !$dayobsPiCrossov &&
			   !$dayobsNpiBnt && !$dayobsNpiPlacebo && !$dayobsNpiCrossov;


		unless (exists $filteredSubjects{$subjectId}->{'earliestCovid'}) {
			$filteredSubjects{$subjectId}->{'earliestCovid'} = undef;
			$filteredSubjects{$subjectId}->{'earliestCovidVisit'} = undef;
		}
		$filteredSubjects{$subjectId}->{'dayobsPiBnt'}       = $dayobsPiBnt;
		$filteredSubjects{$subjectId}->{'dayobsPiPlacebo'}   = $dayobsPiPlacebo;
		$filteredSubjects{$subjectId}->{'dayobsPiCrossov'}   = $dayobsPiCrossov;
		$filteredSubjects{$subjectId}->{'dayobsNpiBnt'}      = $dayobsNpiBnt;
		$filteredSubjects{$subjectId}->{'dayobsNpiPlacebo'}  = $dayobsNpiPlacebo;
		$filteredSubjects{$subjectId}->{'dayobsNpiCrossov'}  = $dayobsNpiCrossov;


		# Increments synthetic stats.
		my $summaryArm = $categoArm;
		if ($summaryArm eq 'Placebo' && $vax201dt) {
			$summaryArm = 'Placebo -> BNT162b2 (30 mcg)';
		}
		if ($summaryArm eq 'Placebo -> BNT162b2 (30 mcg)') {
			$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjects'}++;
			$summaryStats{'byCategoryArms'}->{'totalSubjects'}++;
			$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjects'}++;
			$summaryStats{'bySummaryArms'}->{'totalSubjects'}++;
			if ($aeRowsPostDose3) {
				$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'byCategoryArms'}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'bySummaryArms'}->{'totalSubjectsWithAEs'}++;
			}
			if ($aeserRowsPostDose3) {
				$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'byCategoryArms'}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'bySummaryArms'}->{'totalSubjectsWithSAEs'}++;
			}
		} else {
			$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjects'}++;
			$summaryStats{'byCategoryArms'}->{'totalSubjects'}++;
			$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjects'}++;
			$summaryStats{'bySummaryArms'}->{'totalSubjects'}++;
			if ($aeRows) {
				$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'byCategoryArms'}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjectsWithAEs'}++;
				$summaryStats{'bySummaryArms'}->{'totalSubjectsWithAEs'}++;
			}
			if ($aeserRows) {
				$summaryStats{'byCategoryArms'}->{'byArms'}->{$categoArm}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'byCategoryArms'}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'bySummaryArms'}->{'byArms'}->{$summaryArm}->{'totalSubjectsWithSAEs'}++;
				$summaryStats{'bySummaryArms'}->{'totalSubjectsWithSAEs'}++;
			}
		}

		# printing LinReg .CSV row.
		for my $adslColumn (@adslColumns) {
			my $value = $filteredSubjects{$subjectId}->{$adslColumn} // '';
			print $out5 "$value$csvSeparator";
		}
		say $out5 '';

		# Incrementing AEs statistics.
		if ($aeRows) {
			for my $dt (sort{$a <=> $b} keys %saesByDates) {
				for my $adaeRNum (sort{$a <=> $b} keys %{$saesByDates{$dt}}) {
					print $out6 "$subjectId$csvSeparator";
					for my $adaeColumn (@adaeColumns) {
						my $value = $saesByDates{$dt}->{$adaeRNum}->{$adaeColumn} // '';
						$filteredAEs{$subjectId}->{$adaeRNum}->{$adaeColumn} = $value;
						print $out6 "$value$csvSeparator";
					}
					say $out6 '';
				}
			}
		}
	}
	close $out5;
	close $out6;

	p%tests;
	p%debug;
	p%summaryStats;

	# Formatting filtering details.
	open my $out2, '>:utf8', "public/pt_aes/$path/filtering_details.txt";
	say $out2 "phase1IncludeBNT : $phase1IncludeBNT";
	say $out2 "phase1IncludePlacebo : $phase1IncludePlacebo";
	say $out2 "below16Include : $below16Include";
	say $out2 "seniorsIncluded : $seniorsIncluded";
	say $out2 "duplicatesInclude : $duplicatesInclude";
	say $out2 "noCRFInclude : $noCRFInclude";
	say $out2 "hivSubjectsIncluded : $hivSubjectsIncluded";
	say $out2 "subjectsWithCentralPCR : $subjectsWithCentralPCR";
	say $out2 "subjectsWithNBinding : $subjectsWithNBinding";
	say $out2 "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say $out2 "femaleIncluded : $femaleIncluded";
	say $out2 "maleIncluded : $maleIncluded";
	say $out2 "subjectToUnblinding : $subjectToUnblinding";
	say $out2 "cutoffDate : $cutoffDate";
	say $out2 "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say $out2 "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say $out2 "subjectsWithVoidCOVBLST : $subjectsWithVoidCOVBLST";
	say $out2 "subjectsWithoutSAEs : $subjectsWithoutSAEs";
	say $out2 "aeWithoutDate : $aeWithoutDate";
	say $out2 "csvSeparator : $csvSeparator";
	say $out2 "crossOverCountOnlyBNT : $crossOverCountOnlyBNT";
	my $totalScreenFailures = $filteringStats{'totalScreenFailures'} // die;
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	say $out2 "Preliminary filters : [Screen Failures] ($totalScreenFailures)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'screenFailures'}}) {
		say $out2 $subjectId;
	}
	my $totalNotAssigned = $filteringStats{'totalNotAssigned'} // die;
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	say $out2 "Preliminary filters : [Not Randomized] ($totalNotAssigned)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'notAssigned'}}) {
		say $out2 $subjectId;
	}
	my $totalNotTreated = $filteringStats{'totalNotTreated'} // die;
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	say $out2 "Preliminary filters : [Not Treated] ($totalNotTreated)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'notTreated'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalPhase1BNT = $filteringStats{'totalPhase1BNT'} // $filteringStats{'totalPhase1BNTNotB2_30mcg'} // 0;
	say $out2 "Include phase 1 BNT162b2 30 mcg : [$phase1IncludeBNT] ($totalPhase1BNT)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1BNTNotB2_30mcg'}}) {
		say $out2 $subjectId;
	}
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1BNT'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalPhase1Placebo = $filteringStats{'totalPhase1Placebo'} // 0;
	say $out2 "Include phase 1 Placebo : [$phase1IncludePlacebo] ($totalPhase1Placebo)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'phase1Placebo'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalBelow16 = $filteringStats{'totalBelow16'} // 0;
	say $out2 "Include subjects below 16 : [$below16Include] ($totalBelow16)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'below16'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalAbove54 = $filteringStats{'totalAbove54'} // 0;
	say $out2 "Include subjects below 16 : [$seniorsIncluded] ($totalAbove54)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'above54'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalDuplicates = $filteringStats{'totalDuplicates'} // 0;
	say $out2 "Include duplicates : [$duplicatesInclude] ($totalDuplicates)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'duplicates'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalNoCRFVaxData = $filteringStats{'totalNoCRFVaxData'} // 0;
	say $out2 "Include subjects without CRF Vax Data : [$noCRFInclude] ($totalNoCRFVaxData)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'noCRFVaxData'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalHIVFlags = $filteringStats{'totalHIVFlags'} // 0;
	say $out2 "Include subjects with HIV : [$hivSubjectsIncluded] ($totalHIVFlags)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'hivFlags'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalFemales = $filteringStats{'totalFemales'} // 0;
	say $out2 "Include female subjects : [$femaleIncluded] ($totalFemales)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'females'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalMales = $filteringStats{'totalMales'} // 0;
	say $out2 "Include male subjects : [$maleIncluded] ($totalMales)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'males'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalExcludedFromSafety = $filteringStats{'totalExcludedFromSafety'} // 0;
	say $out2 "Include subjects without Safety Population flag : [$noSafetyPopFlagInclude] ($totalExcludedFromSafety)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'excludedFromSafety'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithPriorInfection = $filteringStats{'totalWithPriorInfection'} // 0;
	say $out2 "Include subjects with prior infection: [$subjectsWithPriorInfect] ($totalWithPriorInfection)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withPriorInfection'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithoutPriorInfection = $filteringStats{'totalWithoutPriorInfection'} // 0;
	say $out2 "Include subjects without prior infection: [$subjectsWithoutPriorInfect] ($totalWithoutPriorInfection)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withoutPriorInfection'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithoutSAEs = $filteringStats{'totalWithoutSAEs'} // 0;
	say $out2 "Include subjects without SAEs: [$subjectsWithoutSAEs] ($totalWithoutSAEs)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withoutSAEs'}}) {
		say $out2 $subjectId;
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalAEsWithoutDate = $filteringStats{'totalAEsWithoutDate'} // 0;
	say $out2 "Include AEs without accurate date: [$aeWithoutDate] ($totalAEsWithoutDate)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'aesWithoutDate'}}) {
		my $total = $filteringStats{'aesWithoutDate'}->{$subjectId} // die;
		say $out2 "$subjectId ($total)";
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalAEsPostUnblind = $filteringStats{'totalAEsPostUnblind'} // 0;
	say $out2 "Include AEs post unblinding: [$subjectToUnblinding] ($totalAEsPostUnblind)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'aesPostUnblind'}}) {
		my $total = $filteringStats{'aesPostUnblind'}->{$subjectId} // die;
		say $out2 "$subjectId ($total)";
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	my $totalWithoutCOVBLST = $filteringStats{'totalWithoutCOVBLST'} // 0;
	say $out2 "Include AEs post unblinding: [$subjectsWithVoidCOVBLST] ($totalWithoutCOVBLST)";
	for my $subjectId (sort{$a <=> $b} keys %{$filteringStats{'withoutCOVBLST'}}) {
		my $total = $filteringStats{'withoutCOVBLST'}->{$subjectId} // die;
		say $out2 "$subjectId ($total)";
	}
	say $out2 "-" x 50;
	say $out2 "-" x 50;
	close $out2;

	# Debug.
	delete $filteringStats{'screenFailures'};
	delete $filteringStats{'notAssigned'};
	delete $filteringStats{'notTreated'};
	delete $filteringStats{'phase1BNTNotB2_30mcg'};
	delete $filteringStats{'phase1BNT'};
	delete $filteringStats{'phase1Placebo'};
	delete $filteringStats{'below16'};
	delete $filteringStats{'above54'};
	delete $filteringStats{'duplicates'};
	delete $filteringStats{'noCRFVaxData'};
	delete $filteringStats{'hivFlags'};
	delete $filteringStats{'lackOfPIOverSight'};
	delete $filteringStats{'females'};
	delete $filteringStats{'males'};
	delete $filteringStats{'excludedFromSafety'};
	delete $filteringStats{'withoutPriorInfection'};
	delete $filteringStats{'withoutCOVBLST'};
	delete $filteringStats{'withPriorInfection'};
	delete $filteringStats{'aesWithoutDate'};
	delete $filteringStats{'saesWithoutDate'};
	delete $filteringStats{'aesPostCutOff'};
	delete $filteringStats{'saesPostCutOff'};
	delete $filteringStats{'aesPostUnblind'};
	delete $filteringStats{'saesPostUnblind'};
	delete $filteringStats{'withoutSAEs'};
	open my $out3, '>:utf8', "public/pt_aes/$path/filtering_abstract.json" or die $!;
	print $out3 encode_json\%filteringStats;
	close $out3;
	# p%filteringStats;
	open my $out4, '>:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.json" or die $!;
	print $out4 encode_json\%filteredSubjects;
	close $out4;
	open my $out7, '>:utf8', "public/pt_aes/$path/filtered_subjects_aes.json" or die $!;
	print $out7 encode_json\%filteredAEs;
	close $out7;

	# Printing main statistics.
	my $toxicityGradeDetails = 0;
	for my $label (sort keys %stats) {
		# p$stats{$label};
		# say "label    : $label";
		# say "ageGroup : $ageGroup";
		my $totalSubjects                = $stats{$label}->{'totalSubjects'}         // next;
		my $totalSubjectsBNT162b2        = $stats{$label}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // die;
		my $totalSubjectsPlacebo         = $stats{$label}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                      // die;
		my $totalSubjectsCrossov         = $stats{$label}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
		my $totalSubjectsWithAE          = $stats{$label}->{'aes'}->{'totalSubjects'}   // next;
		my $totalSubjectsWithSAEs        = $stats{$label}->{'saes'}->{'totalSubjects'} // 0;
		my $dayobsCrossov                = $stats{$label}->{'dayobsCrossov'}         // 0;
		my $dayobsBnt                    = $stats{$label}->{'dayobsBnt'}             // die;
		my $dayobsPlacebo                = $stats{$label}->{'dayobsPlacebo'}         // die;
		my $doeGlobal                    = $dayobsCrossov + $dayobsPlacebo + $dayobsBnt;
		my $personYearsCrossov           = nearest(0.01, $dayobsCrossov / 365);
		my $personYearsBNT162b2          = nearest(0.01, $dayobsBnt     / 365);
		my $personYearsPlacebo           = nearest(0.01, $dayobsPlacebo / 365);
		my $personYearsGlobal            = nearest(0.01, $doeGlobal     / 365);
		$stats{$label}->{'doeGlobal'}           = $doeGlobal;
		$stats{$label}->{'personYearsCrossov'}  = $personYearsCrossov;
		$stats{$label}->{'personYearsBNT162b2'} = $personYearsBNT162b2;
		$stats{$label}->{'personYearsPlacebo'}  = $personYearsPlacebo;
		$stats{$label}->{'personYearsGlobal'}   = $personYearsGlobal;
		# say "label                  : $label";
		# say "ageGroup                 : $ageGroup";
		# say "label                  : $label";
		# say "totalSubjects              : $totalSubjects";
		# say "saes  ->{'totalSubjects'}     : $saes";->{'totalSubjects'}
		# say "doeGlobal                  : $doeGlobal";
		# say "dayobsBnt                : $dayobsBnt";
		# say "dayobsPlacebo                 : $dayobsPlacebo";
		# say "dayobsCrossov       : $dayobsCrossov";
		# say "totalSubjectsWithAE        : $totalSubjectsWithAE";
		# say "personYearsGlobal          : $personYearsGlobal";
		# say "personYearsBNT162b2        : $personYearsBNT162b2";
		# say "personYearsPlacebo         : $personYearsPlacebo";
		# say "personYearsCrossov      : $personYearsCrossov";
		for my $toxicityGrade (sort keys %{$stats{$label}->{'gradeStats'}}) {
			if (!$toxicityGradeDetails) {
				next unless $toxicityGrade eq 'All_Grades';
			}
			# p$stats{$label}->{'gradeStats'}->{$toxicityGrade};
			# say "toxicityGrade              : $toxicityGrade";
			# p$stats{$label};
			say "Printing [public/pt_aes/$path/$label - $toxicityGrade.csv]";
			make_path("public/pt_aes/$path") unless (-d "public/pt_aes/$path");
			open my $out, '>:utf8', "public/pt_aes/$path/$label" . "_$toxicityGrade.csv";
			print $out "System Organ Class / Preferred Term$csvSeparator$csvSeparator".
					 "Total - N=$totalSubjects | PY=$personYearsGlobal$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
					 "BNT162b2 (30 mcg) - N=$totalSubjectsBNT162b2 | PY=$personYearsBNT162b2$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
					 "Placebo - N=$totalSubjectsPlacebo | PY=$personYearsPlacebo$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator";
			if ($personYearsCrossov) {
				print $out "Placebo -> BNT162b2 (30 mcg) - N=$totalSubjectsCrossov | PY=$personYearsCrossov$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator";
			}
			say $out "";
			print $out "$csvSeparator$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator";
			if ($personYearsCrossov) {
				print $out "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					       "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator";
			}
			say $out "";
			my $gradeTotalSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalSubjects'}  // 0;
			my $gradeTotalSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalSubjects'} // 0;
			my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalEvents'}    // 0;
			my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalEvents'} // 0;
			my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'}               // 0;
			my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalEvents'}                         // 0;
			my $placeboBNTAEs                  = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'}    // 0;
			my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'}                          // 0;
			my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalEvents'}                                    // 0;
			my $placeboBNTSAEs                 = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'}               // 0;
			my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'}             // 0;
			my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'}            // 0;
			my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalSubjects'}                       // 0;
			my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalSubjects'}                      // 0;
			my $placeboBNTSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'}  // 0;
			my $placeboBNTSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'} // 0;
			my $rateTotalAEsPer100K            = nearest(0.01, $gradeTotalSubjectsAE  * 100000 / $personYearsGlobal);
			my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE    * 100000 / $personYearsBNT162b2);
			my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE     * 100000 / $personYearsPlacebo);
			my $totalPercentOfTotalAEs         = nearest(0.01, $gradeTotalSubjectsAE  * 100 / $totalSubjects);
			my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE    * 100 / $totalSubjectsBNT162b2);
			my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE     * 100 / $totalSubjectsPlacebo);
			my $rateTotalSAEsPer100K           = nearest(0.01, $gradeTotalSubjectsSAE * 100000 / $personYearsGlobal);
			my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE    * 100000 / $personYearsPlacebo);
			my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE   * 100000 / $personYearsBNT162b2);
			my $totalPercentOfTotalSAEs        = nearest(0.01, $gradeTotalSubjectsSAE * 100 / $totalSubjects);
			my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100 / $totalSubjectsPlacebo);
			my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE   * 100 / $totalSubjectsBNT162b2);
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'rateTotalPer100K'}       = $rateTotalAEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'rateBNT162b2Per100K'}    = $rateBNT162b2AEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'ratePlaceboPer100K'}     = $ratePlaceboAEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'totalPercentOfTotal'}    = $totalPercentOfTotalAEs;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'bntPercentOfTotal'}      = $bnt162B2PercentOfTotalAE;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'placeboPercentOfTotal'}  = $placeboPercentOfTotalAE;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'rateTotalPer100K'}      = $rateTotalSAEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'rateBNT162b2Per100K'}   = $rateBNT162b2SAEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'ratePlaceboPer100K'}    = $ratePlaceboSAEsPer100K;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'totalPercentOfTotal'}   = $totalPercentOfTotalSAEs;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'bntPercentOfTotal'}     = $placeboPercentOfTotalSAE;
			$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'placeboPercentOfTotal'} = $placeboPercentOfTotalSAE;
			# say "totalAEs                   : $totalAEs";
			# say "gradeTotalSubjectsAE       : $gradeTotalSubjectsAE";
			# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
			# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
			# say "totalSAEs                  : $totalSAEs";
			# say "gradeTotalSubjectsSAE      : $gradeTotalSubjectsSAE";
			# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
			print $out "All$csvSeparator" . "All$csvSeparator" .
					   "$totalAEs$csvSeparator$gradeTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
					   "$totalSAEs$csvSeparator$gradeTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
					   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
					   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
					   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
					   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
			if ($personYearsCrossov) {
				my $placeboBNTPercentOfTotalAE     = 0;
				my $placeboBNTPercentOfTotalSAE    = 0;
				if ($totalSubjectsCrossov) {
					$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsCrossov);
					$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsCrossov);
				}
				my $rateCrossovAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsCrossov);
				my $rateCrossovSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsCrossov);
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'crossOvPercentOfTotal'}  = $placeboBNTPercentOfTotalAE;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'aes'}->{'rateCrossOvPer100K'}     = $rateCrossovAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'crossOvPercentOfTotal'} = $placeboBNTPercentOfTotalSAE;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'saes'}->{'rateCrossOvPer100K'}    = $rateCrossovSAEsPer100K;
				print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$rateCrossovAEsPer100K$csvSeparator" .
				           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$rateCrossovSAEsPer100K$csvSeparator";
			}
			say $out "";
			for my $aehlgt (sort keys %{$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}}) {
				my $aehlgtTotalSubjectsAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalSubjects'}         // 0;
				my $aehlgtTotalSubjectsSAE         = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalSubjects'} // 0;
				my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalEvents'} // 0;
				my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalEvents'} // 0;
				my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'}            // 0;
				my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalEvents'}                                // 0;
				my $placeboBNTAEs                  = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'} // 0;
				my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'}            // 0;
				my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalEvents'}                                // 0;
				my $placeboBNTSAEs                 = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'} // 0;
				my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'}            // 0;
				my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'}            // 0;
				my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalSubjects'}                                // 0;
				my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalSubjects'}                                // 0;
				my $placeboBNTSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'} // 0;
				my $placeboBNTSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'} // 0;
				my $rateTotalAEsPer100K            = nearest(0.01, $aehlgtTotalSubjectsAE * 100000 / $personYearsGlobal);
				my $rateTotalSAEsPer100K           = nearest(0.01, $aehlgtTotalSubjectsSAE * 100000 / $personYearsGlobal);
				my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE * 100000 / $personYearsBNT162b2);
				my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE * 100000 / $personYearsBNT162b2);
				my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE * 100000 / $personYearsPlacebo);
				my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE * 100000 / $personYearsPlacebo);
				my $totalPercentOfTotalAEs         = nearest(0.01, $aehlgtTotalSubjectsAE * 100 / $totalSubjects);
				my $totalPercentOfTotalSAEs        = nearest(0.01, $aehlgtTotalSubjectsSAE * 100 / $totalSubjects);
				my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE   * 100 / $totalSubjectsBNT162b2);
				my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE  * 100 / $totalSubjectsBNT162b2);
				my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE    * 100 / $totalSubjectsPlacebo);
				my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100 / $totalSubjectsPlacebo);
				# say "totalAEs                   : $totalAEs";
				# say "gradeTotalSubjectsAE       : $aehlgtTotalSubjectsAE";
				# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
				# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
				# say "totalSAEs                  : $totalSAEs";
				# say "gradeTotalSubjectsSAE      : $aehlgtTotalSubjectsSAE";
				# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'rateTotalPer100K'}       = $rateTotalAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'rateBNT162b2Per100K'}    = $rateBNT162b2AEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'ratePlaceboPer100K'}     = $ratePlaceboAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'totalPercentOfTotal'}    = $totalPercentOfTotalAEs;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'bntPercentOfTotal'}      = $bnt162B2PercentOfTotalAE;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'placeboPercentOfTotal'}  = $placeboPercentOfTotalAE;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'rateTotalPer100K'}      = $rateTotalSAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'rateBNT162b2Per100K'}   = $rateBNT162b2SAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'ratePlaceboPer100K'}    = $ratePlaceboSAEsPer100K;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'totalPercentOfTotal'}   = $totalPercentOfTotalSAEs;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'bntPercentOfTotal'}     = $placeboPercentOfTotalSAE;
				$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'placeboPercentOfTotal'} = $placeboPercentOfTotalSAE;
				print $out "$aehlgt$csvSeparator" . "All$csvSeparator" .
						   "$totalAEs$csvSeparator$aehlgtTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
						   "$totalSAEs$csvSeparator$aehlgtTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
						   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
						   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
						   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
						   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
				if ($personYearsCrossov) {
					my $placeboBNTPercentOfTotalAE     = 0;
					my $placeboBNTPercentOfTotalSAE    = 0;
					if ($totalSubjectsCrossov) {
						$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsCrossov);
						$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsCrossov);
					}
					my $rateCrossovSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsCrossov);
					my $rateCrossovAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsCrossov);
					print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$rateCrossovAEsPer100K$csvSeparator" .
					           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$rateCrossovSAEsPer100K$csvSeparator";
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'crossOvPercentOfTotal'}  = $placeboBNTPercentOfTotalAE;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'aes'}->{'rateCrossOvPer100K'}     = $rateCrossovAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'crossOvPercentOfTotal'} = $placeboBNTPercentOfTotalSAE;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'saes'}->{'rateCrossOvPer100K'}    = $rateCrossovSAEsPer100K;
				}
				say $out "";
				for my $aehlt (sort keys %{$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}}) {
					my $aehltTotalSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalSubjects'}         // 0;
					my $aehltTotalSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalSubjects'} // 0;
					my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalEvents'} // 0;
					my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalEvents'} // 0;
					my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'}            // 0;
					my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalEvents'}                                // 0;
					my $placeboBNTAEs                  = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalEvents'} // 0;
					my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'}            // 0;
					my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalEvents'}                                // 0;
					my $placeboBNTSAEs                 = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalEvents'} // 0;
					my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'}            // 0;
					my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'}            // 0;
					my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'aes'}->{'totalSubjects'}                                // 0;
					my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'saes'}->{'totalSubjects'}                                // 0;
					my $placeboBNTSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'aes'}->{'totalSubjects'} // 0;
					my $placeboBNTSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'saes'}->{'totalSubjects'} // 0;
					my $rateTotalAEsPer100K            = nearest(0.01, $aehltTotalSubjectsAE  * 100000 / $personYearsGlobal);
					my $rateTotalSAEsPer100K           = nearest(0.01, $aehltTotalSubjectsSAE * 100000 / $personYearsGlobal);
					my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE   * 100000 / $personYearsBNT162b2);
					my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE    * 100000 / $personYearsBNT162b2);
					my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE    * 100000 / $personYearsPlacebo);
					my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE     * 100000 / $personYearsPlacebo);
					my $totalPercentOfTotalAEs         = nearest(0.01, $aehltTotalSubjectsAE  * 100    / $totalSubjects);
					my $totalPercentOfTotalSAEs        = nearest(0.01, $aehltTotalSubjectsSAE * 100    / $totalSubjects);
					my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE    * 100    / $totalSubjectsBNT162b2);
					my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE   * 100    / $totalSubjectsBNT162b2);
					my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE     * 100    / $totalSubjectsPlacebo);
					my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100    / $totalSubjectsPlacebo);
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'rateTotalPer100K'}       = $rateTotalAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'rateBNT162b2Per100K'}    = $rateBNT162b2AEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'ratePlaceboPer100K'}     = $ratePlaceboAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'totalPercentOfTotal'}    = $totalPercentOfTotalAEs;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'bntPercentOfTotal'}      = $bnt162B2PercentOfTotalAE;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'placeboPercentOfTotal'}  = $placeboPercentOfTotalAE;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'rateTotalPer100K'}      = $rateTotalSAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'rateBNT162b2Per100K'}   = $rateBNT162b2SAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'ratePlaceboPer100K'}    = $ratePlaceboSAEsPer100K;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'totalPercentOfTotal'}   = $totalPercentOfTotalSAEs;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'bntPercentOfTotal'}     = $placeboPercentOfTotalSAE;
					$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'placeboPercentOfTotal'} = $placeboPercentOfTotalSAE;
					# say "totalAEs                   : $totalAEs";
					# say "gradeTotalSubjectsAE       : $aehlgtTotalSubjectsAE";
					# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
					# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
					# say "totalSAEs                  : $totalSAEs";
					# say "gradeTotalSubjectsSAE      : $aehlgtTotalSubjectsSAE";
					# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
					print $out "$csvSeparator$aehlt$csvSeparator" .
							   "$totalAEs$csvSeparator$aehltTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
							   "$totalSAEs$csvSeparator$aehltTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
							   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
							   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
							   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
							   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
					if ($personYearsCrossov) {
						my $placeboBNTPercentOfTotalAE     = 0;
						my $placeboBNTPercentOfTotalSAE    = 0;
						if ($totalSubjectsCrossov) {
							$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsCrossov);
							$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsCrossov);
						}
						my $rateCrossovSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsCrossov);
						my $rateCrossovAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsCrossov);
						print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$rateCrossovAEsPer100K$csvSeparator" .
						           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$rateCrossovSAEsPer100K$csvSeparator";
						$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'crossOvPercentOfTotal'}  = $placeboBNTPercentOfTotalAE;
						$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'aes'}->{'rateCrossOvPer100K'}     = $rateCrossovAEsPer100K;
						$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'crossOvPercentOfTotal'} = $placeboBNTPercentOfTotalSAE;
						$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'saes'}->{'rateCrossOvPer100K'}    = $rateCrossovSAEsPer100K;
					}
					say $out "";
			# 		say $out ";$aehlt;$aesBNT162b2;$saesBNT162b2;$bNT162b2Subjects;$bnt162B2PercentOfTotal;$placeboAEs;$placeboSAEs;$placeboSubjectsAE;$placeboPercentOfTotalAE;$placeboBNTAEs;$placeboBNTSAEs;$placeboBNTSubjectsAE;$placeboBNTPercentOfTotalAE;$aehltTotalAEs;$aehltTotalSAEs;$aehltTotalSubjects;$totalPercentOfTotalAEs;";
				}
			}
			close $out;
		}
	}

	# Printing end-usage stats.
	open my $out8, '>:utf8', "public/pt_aes/$path/detailed_stats.json" or die $!;
	print $out8 encode_json\%stats;
	close $out8;

	# printing summary stats.
	open my $out9, '>:utf8', "public/pt_aes/$path/summary_stats.json" or die $!;
	print $out9 encode_json\%summaryStats;
	close $out9;

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	$self->render(
		path => $path,
		subjectsWithCentralPCR => $subjectsWithCentralPCR,
		subjectsWithNBinding => $subjectsWithNBinding,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    noCRFInclude => $noCRFInclude,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    aeWithoutDate => $aeWithoutDate,
	    currentLanguage => $currentLanguage,
	    languages => \%languages
	);
}

sub subject_central_pcrs_by_visits {
	my ($subjectId, $cutoffCompdate, %subjectData) = @_;
	my $posPCR = 0;
	for my $visit (sort keys %{$subjectData{'pcrs'}}) {
		my $visitcpdt = $subjectData{'pcrs'}->{$visit}->{'visitcpdt'} // die;
		my $mborres   = $subjectData{'pcrs'}->{$visit}->{'mborres'}   // die;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitcpdt >= 20200720;
		next unless $visitcpdt <= $cutoffCompdate;
		if ($mborres eq 'POS') {
			$posPCR = 1;
		} elsif ($mborres eq 'NEG') {
		} elsif ($mborres eq 'IND' || $mborres eq '') {
		} else {
			die "mborres : $mborres";
		}
	}
	return $posPCR;
}

sub subject_symptoms_by_visits {
	my ($subjectId, $cutoffCompdate, %subjectData) = @_;
	# p$subjectData{'symptoms'};
	my $hasSymptoms = 0;
	for my $visit (sort keys %{$subjectData{'symptoms'}}) {
		my $symptomCompdate = $subjectData{'symptoms'}->{$visit}->{'symptomCompdate'} // die;

		# Skips the visit unless it fits with the phase 3.
		next unless $symptomCompdate >= 20200720;
		next unless $symptomCompdate <= $cutoffCompdate;
		die unless keys %{$subjectData{'symptoms'}->{$visit}->{'symptoms'}};
		$hasSymptoms = 1;
	}
	return $hasSymptoms;
}

sub subject_central_nbindings_by_visits {
	my ($subjectId, $cutoffCompdate, %subjectData) = @_;
	my $posNBinding = 0;
	for my $visit (sort keys %{$subjectData{'nBindings'}}) {
		my $visitcpdt = $subjectData{'nBindings'}->{$visit}->{'visitcpdt'} // die;
		my $avalc     = $subjectData{'nBindings'}->{$visit}->{'avalc'}     // die;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitcpdt >= 20200720;
		next unless $visitcpdt <= $cutoffCompdate;
		if ($avalc eq 'POS') {
			$posNBinding = 1;
		} elsif ($avalc eq 'NEG') {
		} elsif ($avalc eq 'IND' || $avalc eq '') {
		} else {
			die "avalc : $avalc";
		}
	}
	return $posNBinding;
}

sub time_of_exposure_from_simple {
	my ($actarm, $vax101dt, $vax102dt, $vax201dt, $dthdt, $deathcptdt, $limitDateh, $limitDate) = @_;
	my ($dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov) = (0, 0, 0);
	my $groupArm = $actarm;
	if ($actarm ne 'Placebo') {
		$groupArm = 'BNT162b2 (30 mcg)';
	}
	if ($vax201dt) {
		die unless $actarm eq 'Placebo';
		$groupArm = 'Placebo -> BNT162b2 (30 mcg)';
		$dayobsPiPlacebo = time::calculate_days_difference($vax101dt, $vax201dt);
		if ($dthdt && ($deathcptdt < $limitDate)) {
			$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $dthdt);
		} else {
			my ($v2cp) = split ' ', $vax201dt;
			$v2cp =~ s/\D//g;
			if ($limitDate > $v2cp) {
				$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $limitDateh);
			}
		}
	} else {
		my $daysBetweenDoseAndCutOff;
		if ($dthdt && ($deathcptdt < $limitDate)) {
			$daysBetweenDoseAndCutOff = time::calculate_days_difference($vax101dt, $dthdt);
		} else {
			$daysBetweenDoseAndCutOff = time::calculate_days_difference($vax101dt, $limitDateh);
		}
		if ($actarm eq 'Placebo') {
			$dayobsPiPlacebo += $daysBetweenDoseAndCutOff;
		} else {
			$dayobsPiBnt     += $daysBetweenDoseAndCutOff;	
		}
	}
	return ($groupArm, $dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov);
}

sub time_of_exposure_from_conflicting {
    my ($label, $actarm, $vax101dt, $vax102dt, $vax201dt, $vax202dt, $dthdt, $deathcptdt, $limitDateh, $limitDate, $earliestCovid, $lastDosePriorCovid, $lastDosePriorCovidDate) = @_;
	# say "$label, $actarm, $vax101dt, $vax102dt, $vax201dt, $vax202dt, $dthdt, $deathcptdt, $limitDateh, $limitDate, $earliestCovid, $lastDosePriorCovid, $lastDosePriorCovidDate";
    my ($dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov) = (0, 0, 0);
    my $groupArm = $actarm;
	if ($actarm ne 'Placebo') {
		$groupArm = 'BNT162b2 (30 mcg)';
	}
	my $treatmentCutoffCompdate = $limitDate;
    if ($lastDosePriorCovid >= 1 && $lastDosePriorCovid <= 3) {
        my ($daysBetweenDoseAndCutOff, $lastDoseDatetime);
        if ($lastDosePriorCovid == 1) {
            $lastDoseDatetime = $vax102dt || $vax201dt;
        } elsif ($lastDosePriorCovid == 2) {
            $lastDoseDatetime = $vax201dt;
        } elsif ($lastDosePriorCovid == 3) {
            $lastDoseDatetime = $vax202dt;
        } else {
        	die;
        }
        my ($lastDoseDate) = split ' ', $lastDoseDatetime;
        $lastDoseDate =~ s/\D//g;
        if ($label eq 'Doses_Without_Infection') {
        	if (!$vax201dt && !$vax202dt) {
	            $daysBetweenDoseAndCutOff = time::calculate_days_difference($vax101dt, $lastDoseDatetime);
	            if ($actarm eq 'Placebo') {
	                $dayobsPiPlacebo += $daysBetweenDoseAndCutOff;
	            } else {
	                $dayobsPiBnt     += $daysBetweenDoseAndCutOff;
	            }
        	} else {
        		die unless $vax201dt;
	            $daysBetweenDoseAndCutOff = time::calculate_days_difference($vax101dt, $vax201dt);
	            if ($actarm eq 'Placebo') {
	                $dayobsPiPlacebo += $daysBetweenDoseAndCutOff;
	            } else {
	                $dayobsPiBnt     += $daysBetweenDoseAndCutOff;
	            }
        	}
            if ($lastDosePriorCovid > 2) {
            	die unless $vax201dt && $vax202dt;
				my ($v3cp) = split ' ', $vax201dt;
				$v3cp =~ s/\D//g;
				if ($v3cp <= $limitDate) {
	                $dayobsPiCrossov = time::calculate_days_difference($vax201dt, $vax201dt);
				}
            }
	        if ($lastDosePriorCovid == 1) {
	        	if ($vax102dt) {
            		($treatmentCutoffCompdate) = split ' ', $vax102dt;
        		} else {
            		($treatmentCutoffCompdate) = split ' ', $vax201dt;
        		}
	        } elsif ($lastDosePriorCovid == 2) {
        		($treatmentCutoffCompdate) = split ' ', $vax201dt;
	        } elsif ($lastDosePriorCovid == 3) {
        		($treatmentCutoffCompdate) = split ' ', $vax202dt;
	        }
            $treatmentCutoffCompdate   =~ s/\D//g;
        } elsif ($label eq 'Doses_With_Infection') {
            if ($lastDosePriorCovid == 1 && $vax102dt && $vax201dt) {
                $groupArm = 'Placebo -> BNT162b2 (30 mcg)';
                $dayobsPiPlacebo = time::calculate_days_difference($vax102dt, $vax201dt);
				my ($v3cp) = split ' ', $vax201dt;
				$v3cp =~ s/\D//g;
                if ($dthdt && ($deathcptdt < $limitDate) && ($limitDate > $v3cp)) {
                	$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $dthdt);
                } elsif ($limitDate > $v3cp) {
					$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $limitDateh);
                }
            } elsif ($lastDosePriorCovid == 1 && $vax201dt) {
                $groupArm = 'Placebo -> BNT162b2 (30 mcg)';
                $dayobsPiPlacebo = time::calculate_days_difference($vax101dt, $vax201dt);
				my ($v3cp) = split ' ', $vax201dt;
				$v3cp =~ s/\D//g;
                if ($dthdt && ($deathcptdt < $limitDate) && ($limitDate > $v3cp)) {
                	$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $dthdt);
                } elsif ($limitDate > $v3cp) {
					$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $limitDateh);
                }
            } elsif ($lastDosePriorCovid == 1 && $vax102dt) {
				my ($v2cp) = split ' ', $vax102dt;
				$v2cp =~ s/\D//g;
                if ($dthdt && ($deathcptdt < $limitDate) && ($limitDate > $v2cp)) {
                	$daysBetweenDoseAndCutOff = time::calculate_days_difference($vax102dt, $dthdt);
                } elsif ($limitDate > $v2cp) {
					$daysBetweenDoseAndCutOff = time::calculate_days_difference($vax102dt, $limitDateh);
                }
	            if ($actarm eq 'Placebo') {
	                $dayobsPiPlacebo += $daysBetweenDoseAndCutOff;
	            } else {
	                $dayobsPiBnt     += $daysBetweenDoseAndCutOff;
	            }
            } elsif ($lastDosePriorCovid == 2 && $vax201dt) {
                $groupArm = 'Placebo -> BNT162b2 (30 mcg)';
                $dayobsPiPlacebo = time::calculate_days_difference($vax101dt, $vax201dt);
				my ($v3cp) = split ' ', $vax201dt;
				$v3cp =~ s/\D//g;
                if ($dthdt && ($deathcptdt < $limitDate) && ($limitDate > $v3cp)) {
                	$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $dthdt);
                } elsif ($limitDate > $v3cp) {
					$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $limitDateh);
                }
            } elsif ($lastDosePriorCovid == 3 && $vax202dt) {
                $groupArm = 'Placebo -> BNT162b2 (30 mcg)';
                $dayobsPiPlacebo = time::calculate_days_difference($vax101dt, $vax202dt);
                if ($dthdt && ($deathcptdt < $limitDate)) {
                    $dayobsPiCrossov = time::calculate_days_difference($vax202dt, $dthdt)
                } else {
					my ($v2cp) = split ' ', $vax202dt;
					$v2cp =~ s/\D//g;
					if ($limitDate > $v2cp) {
						$dayobsPiCrossov = time::calculate_days_difference($vax202dt, $limitDateh);
					}
                }
				my ($v4cp) = split ' ', $vax202dt;
				$v4cp =~ s/\D//g;
                if ($dthdt && ($deathcptdt < $limitDate) && ($limitDate > $v4cp)) {
                	$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $dthdt);
                } elsif ($limitDate > $v4cp) {
					$dayobsPiCrossov = time::calculate_days_difference($vax201dt, $limitDateh);
                }
            } else { die "lastDosePriorCovid : $lastDosePriorCovid" }
        } else { die "$label && $lastDoseDatetime" }
    } else {
    	die;
    }
	return ($groupArm, $dayobsPiBnt, $dayobsPiPlacebo, $dayobsPiCrossov, $treatmentCutoffCompdate);
}

sub render_logs {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $subjectsWithSymptoms = $self->param('subjectsWithSymptoms') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $subjectsWithVoidCOVBLST = $self->param('subjectsWithVoidCOVBLST') // die;
	my $crossOverCountOnlyBNT = $self->param('crossOverCountOnlyBNT') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	say "path : [$path]";
	say "phase1IncludeBNT : $phase1IncludeBNT";
	say "crossOverCountOnlyBNT : $crossOverCountOnlyBNT";
	say "phase1IncludePlacebo : $phase1IncludePlacebo";
	say "below16Include : $below16Include";
	say "seniorsIncluded : $seniorsIncluded";
	say "duplicatesInclude : $duplicatesInclude";
	say "noCRFInclude : $noCRFInclude";
	say "hivSubjectsIncluded : $hivSubjectsIncluded";
	say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	say "femaleIncluded : $femaleIncluded";
	say "maleIncluded : $maleIncluded";
	say "subjectToUnblinding : $subjectToUnblinding";
	say "cutoffDate : $cutoffDate";
	say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "aeWithoutDate : $aeWithoutDate";
	say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtering_abstract.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteringStats = %$json1;
	p%filteringStats;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    aeWithoutDate => $aeWithoutDate,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    filteringStats => \%filteringStats
	);
}

sub render_lin_reg_data {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $subjectsWithVoidCOVBLST = $self->param('subjectsWithVoidCOVBLST') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $subjectsWithSymptoms = $self->param('subjectsWithSymptoms') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $crossOverCountOnlyBNT = $self->param('crossOverCountOnlyBNT') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	# say "path : [$path]";
	# say "phase1IncludeBNT : $phase1IncludeBNT";
	# say "phase1IncludePlacebo : $phase1IncludePlacebo";
	# say "below16Include : $below16Include";
	# say "seniorsIncluded : $seniorsIncluded";
	# say "duplicatesInclude : $duplicatesInclude";
	# say "noCRFInclude : $noCRFInclude";
	# say "hivSubjectsIncluded : $hivSubjectsIncluded";
	# say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	# say "femaleIncluded : $femaleIncluded";
	# say "maleIncluded : $maleIncluded";
	# say "subjectToUnblinding : $subjectToUnblinding";
	# say "cutoffDate : $cutoffDate";
	# say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	# say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	# say "aeWithoutDate : $aeWithoutDate";
	# say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtered_subjects_lin_reg.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteredSubjects = %$json1;
	# p%filteredSubjects;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    filteredSubjects => \%filteredSubjects,
	    adslColumns => \@adslColumns
	);
}

sub render_stats {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $subjectsWithCentralPCR = $self->param('subjectsWithCentralPCR') // die;
	my $subjectsWithNBinding = $self->param('subjectsWithNBinding') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $subjectsWithVoidCOVBLST = $self->param('subjectsWithVoidCOVBLST') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $subjectsWithSymptoms = $self->param('subjectsWithSymptoms') // die;
	my $crossOverCountOnlyBNT = $self->param('crossOverCountOnlyBNT') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	# say "path : [$path]";
	# say "phase1IncludeBNT : $phase1IncludeBNT";
	# say "phase1IncludePlacebo : $phase1IncludePlacebo";
	# say "below16Include : $below16Include";
	# say "seniorsIncluded : $seniorsIncluded";
	# say "duplicatesInclude : $duplicatesInclude";
	# say "noCRFInclude : $noCRFInclude";
	# say "hivSubjectsIncluded : $hivSubjectsIncluded";
	# say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	# say "femaleIncluded : $femaleIncluded";
	# say "maleIncluded : $maleIncluded";
	# say "subjectToUnblinding : $subjectToUnblinding";
	# say "cutoffDate : $cutoffDate";
	# say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	# say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	# say "aeWithoutDate : $aeWithoutDate";
	# say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/summary_stats.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %stats = %$json1;
	p%stats;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
		subjectsWithCentralPCR => $subjectsWithCentralPCR,
		subjectsWithNBinding => $subjectsWithNBinding,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    femaleIncluded => $femaleIncluded,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    maleIncluded => $maleIncluded,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    stats => \%stats
	);
}

sub render_aes_data {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $crossOverCountOnlyBNT = $self->param('crossOverCountOnlyBNT') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $subjectsWithVoidCOVBLST = $self->param('subjectsWithVoidCOVBLST') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $subjectsWithSymptoms = $self->param('subjectsWithSymptoms') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	# say "path : [$path]";
	# say "phase1IncludeBNT : $phase1IncludeBNT";
	# say "phase1IncludePlacebo : $phase1IncludePlacebo";
	# say "below16Include : $below16Include";
	# say "seniorsIncluded : $seniorsIncluded";
	# say "duplicatesInclude : $duplicatesInclude";
	# say "noCRFInclude : $noCRFInclude";
	# say "hivSubjectsIncluded : $hivSubjectsIncluded";
	# say "noSafetyPopFlagInclude : $noSafetyPopFlagInclude";
	# say "femaleIncluded : $femaleIncluded";
	# say "maleIncluded : $maleIncluded";
	# say "subjectToUnblinding : $subjectToUnblinding";
	# say "cutoffDate : $cutoffDate";
	# say "subjectsWithPriorInfect : $subjectsWithPriorInfect";
	# say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	# say "aeWithoutDate : $aeWithoutDate";
	# say "csvSeparator : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/filtered_subjects_aes.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %filteredAEs = %$json1;
	# p%filteredAEs;

	$self->render(
		path => $path,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    femaleIncluded => $femaleIncluded,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    maleIncluded => $maleIncluded,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    filteredAEs => \%filteredAEs,
	    adaeColumns => \@adaeColumns
	);
}

sub stats_details {
	my $self = shift;
	my $currentLanguage = $self->param('currentLanguage') // 'en';
	my $path = $self->param('path') // die;
	my $crossOverCountOnlyBNT = $self->param('crossOverCountOnlyBNT') // die;
	my $subjectsWithCentralPCR = $self->param('subjectsWithCentralPCR') // die;
	my $subjectsWithVoidCOVBLST = $self->param('subjectsWithVoidCOVBLST') // die;
	my $subjectsWithNBinding = $self->param('subjectsWithNBinding') // die;
	my $phase1IncludeBNT = $self->param('phase1IncludeBNT') // die;
	my $subjectsWithSymptoms = $self->param('subjectsWithSymptoms') // die;
	my $phase1IncludePlacebo = $self->param('phase1IncludePlacebo') // die;
	my $subjectsWithoutSAEs = $self->param('subjectsWithoutSAEs') // die;
	my $aeWithoutDate = $self->param('aeWithoutDate') // die;
	my $below16Include = $self->param('below16Include') // die;
	my $seniorsIncluded = $self->param('seniorsIncluded') // die;
	my $duplicatesInclude = $self->param('duplicatesInclude') // die;
	my $noCRFInclude = $self->param('noCRFInclude') // die;
	my $hivSubjectsIncluded = $self->param('hivSubjectsIncluded') // die;
	my $noSafetyPopFlagInclude = $self->param('noSafetyPopFlagInclude') // die;
	my $femaleIncluded = $self->param('femaleIncluded') // die;
	my $maleIncluded = $self->param('maleIncluded') // die;
	my $subjectToUnblinding = $self->param('subjectToUnblinding') // die;
	my $cutoffDate = $self->param('cutoffDate') // die;
	my $subjectsWithPriorInfect = $self->param('subjectsWithPriorInfect') // die;
	my $subjectsWithoutPriorInfect = $self->param('subjectsWithoutPriorInfect') // die;
	my $csvSeparator = $self->param('csvSeparator') // die;
	my $currentTab = $self->param('currentTab') // die;
	my $displayedEvents = $self->param('displayedEvents') // die;
	my $currentTabName = 'Doses_Without_Infection';
	$currentTabName = 'Doses_With_Infection' if $currentTab eq 'withPrior';
	say "path                       : [$path]";
	say "displayedEvents            : $displayedEvents";
	say "currentTab                 : $currentTab";
	say "currentTabName             : $currentTabName";
	say "phase1IncludeBNT           : $phase1IncludeBNT";
	say "phase1IncludePlacebo       : $phase1IncludePlacebo";
	say "below16Include             : $below16Include";
	say "seniorsIncluded            : $seniorsIncluded";
	say "duplicatesInclude          : $duplicatesInclude";
	say "crossOverCountOnlyBNT      : $crossOverCountOnlyBNT";
	say "noCRFInclude               : $noCRFInclude";
	say "hivSubjectsIncluded        : $hivSubjectsIncluded";
	say "noSafetyPopFlagInclude     : $noSafetyPopFlagInclude";
	say "femaleIncluded             : $femaleIncluded";
	say "maleIncluded               : $maleIncluded";
	say "subjectToUnblinding        : $subjectToUnblinding";
	say "cutoffDate                 : $cutoffDate";
	say "subjectsWithPriorInfect    : $subjectsWithPriorInfect";
	say "subjectsWithoutPriorInfect : $subjectsWithoutPriorInfect";
	say "aeWithoutDate              : $aeWithoutDate";
	say "csvSeparator               : $csvSeparator";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

	# Loading filtering log abstract.
	open my $in1, '<:utf8', "public/pt_aes/$path/detailed_stats.json";
	my $json1;
	while (<$in1>) {
		$json1 .= $_;
	}
	close $in1;
	$json1 = decode_json($json1);
	my %stats = %$json1;
	die unless exists $stats{$currentTabName};
	%stats = %{$stats{$currentTabName}};
	# delete $stats{'gradeStats'};
	# p%stats;

	$self->render(
		path => $path,
	    currentTab => $currentTab,
	    currentTabName => $currentTabName,
	    displayedEvents => $displayedEvents,
	    phase1IncludeBNT => $phase1IncludeBNT,
	    phase1IncludePlacebo => $phase1IncludePlacebo,
		subjectsWithSymptoms => $subjectsWithSymptoms,
	    aeWithoutDate => $aeWithoutDate,
	    below16Include => $below16Include,
	    seniorsIncluded => $seniorsIncluded,
	    duplicatesInclude => $duplicatesInclude,
	    crossOverCountOnlyBNT => $crossOverCountOnlyBNT,
	    noCRFInclude => $noCRFInclude,
	    hivSubjectsIncluded => $hivSubjectsIncluded,
	    noSafetyPopFlagInclude => $noSafetyPopFlagInclude,
	    subjectsWithoutSAEs => $subjectsWithoutSAEs,
	    femaleIncluded => $femaleIncluded,
	    maleIncluded => $maleIncluded,
	    subjectsWithVoidCOVBLST => $subjectsWithVoidCOVBLST,
	    subjectToUnblinding => $subjectToUnblinding,
	    cutoffDate => $cutoffDate,
	    subjectsWithPriorInfect => $subjectsWithPriorInfect,
	    subjectsWithoutPriorInfect => $subjectsWithoutPriorInfect,
	    csvSeparator => $csvSeparator,
	    currentLanguage => $currentLanguage,
	    languages => \%languages,
	    stats => \%stats,
	    adslColumns => \@adslColumns
	);
}

1;
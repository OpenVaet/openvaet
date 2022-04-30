package OpenVaet::Controller::Index;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Email::Valid;
use Math::Round qw(nearest);
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub index {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $fetchedStat     = $self->param('fetchedStat')     // 'deaths';
    my $fromYear        = $self->param('fromYear')        // '2020';
    my $toYear          = $self->param('toYear')          // '2022';
    my $fromAge         = $self->param('fromAge')         // '0m';
    my $toAge           = $self->param('toAge')           // '17y';
    my $reporter        = $self->param('reporter')        // 'na';
    my $sexGroup        = $self->param('sexGroup')        // 'na';
    say "currentLanguage : [$currentLanguage]";
    say "fetchedStat     : [$fetchedStat]";
    say "fromAge         : [$fromAge]";
    say "toAge           : [$toAge]";
    say "reporter        : [$reporter]";
    say "sexGroup        : [$sexGroup]";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'Français';
    $languages{'en'} = 'English';

    # Formatting forms.
    my %fetchedStats = ();
    if ($currentLanguage eq 'en') {
        $fetchedStats{'1'}->{'label'} = 'Deaths';
        $fetchedStats{'2'}->{'label'} = 'Serious Cases';
        $fetchedStats{'3'}->{'label'} = 'Non Serious Cases';
    } elsif ($currentLanguage eq 'fr') {
        $fetchedStats{'1'}->{'label'} = 'Décès';
        $fetchedStats{'2'}->{'label'} = 'Cas Sérieux';
        $fetchedStats{'3'}->{'label'} = 'Cas Non-Sérieux';
    } else {

    }
    $fetchedStats{'1'}->{'value'} = 'deaths';
    $fetchedStats{'2'}->{'value'} = 'serious';
    $fetchedStats{'3'}->{'value'} = 'nonSerious';
    
    my %fromYears = ();
    my $fYNum = 0;
    for my $year (1994 .. 2022) {
        $fYNum++;
        $fromYears{$fYNum}->{'label'} = $year;
        $fromYears{$fYNum}->{'value'} = $year;
    }
    my %toYears = ();
    my $tYNum = 0;;
    for my $year (1995 .. 2022) {
        $tYNum++;
        $toYears{$tYNum}->{'label'} = $year;
        $toYears{$tYNum}->{'value'} = $year;
    }
    
    my %fromAges = ();
    $fromAges{'1'}->{'ageType'} = 'month';
    $fromAges{'1'}->{'label'} = '0';
    $fromAges{'1'}->{'value'} = '0m';
    $fromAges{'2'}->{'ageType'} = 'month';
    $fromAges{'2'}->{'label'} = '2';
    $fromAges{'2'}->{'value'} = '2m';
    $fromAges{'3'}->{'ageType'} = 'year';
    $fromAges{'3'}->{'label'} = '3';
    $fromAges{'3'}->{'value'} = '3y';
    $fromAges{'4'}->{'ageType'} = 'year';
    $fromAges{'4'}->{'label'} = '12';
    $fromAges{'4'}->{'value'} = '12y';
    $fromAges{'5'}->{'ageType'} = 'year';
    $fromAges{'5'}->{'label'} = '18';
    $fromAges{'5'}->{'value'} = '18y';
    $fromAges{'6'}->{'ageType'} = 'year';
    $fromAges{'6'}->{'label'} = '65';
    $fromAges{'6'}->{'value'} = '65y';
    $fromAges{'7'}->{'ageType'} = 'year';
    $fromAges{'7'}->{'label'} = '85+';
    $fromAges{'7'}->{'value'} = '85y';

    my %toAges = ();
    $toAges{'1'}->{'ageType'} = 'month';
    $toAges{'1'}->{'label'} = '1';
    $toAges{'1'}->{'value'} = '1m';
    $toAges{'2'}->{'ageType'} = 'year';
    $toAges{'2'}->{'label'} = '2';
    $toAges{'2'}->{'value'} = '2y';
    $toAges{'3'}->{'ageType'} = 'year';
    $toAges{'3'}->{'label'} = '11';
    $toAges{'3'}->{'value'} = '11y';
    $toAges{'4'}->{'ageType'} = 'year';
    $toAges{'4'}->{'label'} = '17';
    $toAges{'4'}->{'value'} = '17y';
    $toAges{'5'}->{'ageType'} = 'year';
    $toAges{'5'}->{'label'} = '64';
    $toAges{'5'}->{'value'} = '64y';
    $toAges{'6'}->{'ageType'} = 'year';
    $toAges{'6'}->{'label'} = '85';
    $toAges{'6'}->{'value'} = '85y';
    $toAges{'7'}->{'ageType'} = 'year';
    $toAges{'7'}->{'label'} = '85+';
    $toAges{'7'}->{'value'} = '86y';

    my %sexGroups = ();
    $sexGroups{'1'}->{'value'} = 'na';
    $sexGroups{'2'}->{'value'} = 'f';
    $sexGroups{'3'}->{'value'} = 'm';
    if ($currentLanguage eq 'en') {
        $sexGroups{'1'}->{'label'} = 'Indifferent';
        $sexGroups{'2'}->{'label'} = 'Female';
        $sexGroups{'3'}->{'label'} = 'Male';
    } elsif ($currentLanguage eq 'fr') {
        $sexGroups{'1'}->{'label'} = 'Indifférent';
        $sexGroups{'2'}->{'label'} = 'Femme';
        $sexGroups{'3'}->{'label'} = 'Homme';
    } else {

    }

    my %reporters = ();
    $reporters{'1'}->{'value'} = 'na';
    $reporters{'2'}->{'value'} = 'md';
    $reporters{'3'}->{'value'} = 'nmd';
    if ($currentLanguage eq 'en') {
        $reporters{'1'}->{'label'} = 'Indifferent';
        $reporters{'2'}->{'label'} = 'Medical Professional';
        $reporters{'3'}->{'label'} = 'Non Medical Professionals';
    } elsif ($currentLanguage eq 'fr') {
        $reporters{'1'}->{'label'} = 'Indifférent';
        $reporters{'2'}->{'label'} = 'Professionnel Médical';
        $reporters{'3'}->{'label'} = 'Non Professionnel Médical';
    } else {

    }

    my $covidTotalCases           = 0;
    my $covidPlusOthersTotalCases = 0;
    my $allOthersTotalCases       = 0;
    my $covidTotalDrugs           = 0;
    my $allOthersTotalDrugs       = 0;
    my $statsFile                 = "stats.json";
    my %substancesFetched         = ();
    if (-f $statsFile) {
        my $json;
        open my $in, '<:utf8', $statsFile;
        while (<$in>) {
            $json .= $_;
        }
        close $in;
        my $stats = decode_json($json);
        my %stats = %$stats;
        if (exists $stats{'eventsCategorized'}->{$fetchedStat}) {
            for my $yearName (sort{$a <=> $b} keys %{$stats{'eventsCategorized'}->{$fetchedStat}}) {
                if ($fromYear ne 'NA') {
                    next if $fromYear > $yearName;
                }
                next if $toYear  < $yearName;
                for my $reporterTypeName (sort keys %{$stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}}) {
                    if ($reporter ne 'na') {
                        if ($reporter eq 'md') {
                            next if $reporterTypeName ne 'Healthcare Professional';
                        } elsif ($reporter eq 'nmd') {
                            next if $reporterTypeName eq 'Healthcare Professional';
                        } else {
                            die "reporter : $reporter";
                        }
                    }
                    for my $ageGroupName (sort keys %{$stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}}) {
                        if ($fromAge ne '0m') {
                            if ($fromAge eq '2m') {
                                next if $ageGroupName eq '0-1 Month';
                            } elsif ($fromAge eq '3y') {
                                next if $ageGroupName eq '0-1 Month' || $ageGroupName eq '2 Months - 2 Years';
                            } elsif ($fromAge eq '12y') {
                                next if $ageGroupName eq '0-1 Month' || $ageGroupName eq '2 Months - 2 Years' || $ageGroupName eq '3 Years - 11 Years';
                            } elsif ($fromAge eq '18y') {
                                next if $ageGroupName ne '18-64 Years' && $ageGroupName ne '65-85 Years' && $ageGroupName ne 'More than 85 Years';
                            } elsif ($fromAge eq '65y') {
                                next if $ageGroupName ne '65-85 Years' && $ageGroupName ne 'More than 85 Years';
                            } elsif ($fromAge eq '85y') {
                                next if $ageGroupName ne 'More than 85 Years';
                            } else {
                                die "fromAge : $fromAge";
                            }
                        }
                        if ($toAge ne '86y') {
                            if ($toAge eq '1m') {
                                next if $ageGroupName ne '0-1 Month';
                            } elsif ($toAge eq '2y') {
                                next if $ageGroupName ne '0-1 Month' && $ageGroupName ne '2 Months - 2 Years';
                            } elsif ($toAge eq '11y') {
                                next if $ageGroupName ne '0-1 Month' && $ageGroupName ne '2 Months - 2 Years' && $ageGroupName ne '3 Years - 11 Years';
                            } elsif ($toAge eq '17y') {
                                next if $ageGroupName eq '18-64 Years' || $ageGroupName eq '65-85 Years' || $ageGroupName eq 'More than 85 Years';
                            } elsif ($toAge eq '64y') {
                                next if $ageGroupName eq '65-85 Years' || $ageGroupName eq 'More than 85 Years';
                            } elsif ($toAge eq '85y') {
                                next if $ageGroupName eq 'More than 85 Years';
                            } else {
                                die "toAge : $toAge";
                            }
                        }
                        for my $sexName (sort keys %{$stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}}) {
                            my $covidAfterEffects = $stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{'COVID19'} // 0;
                            my $otherVaccinesAfterEffects = $stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{'OTHER'} // 0;
                            my $covidPlusOtherVaccinesAfterEffects = $stats{'eventsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{'COVID19+OTHER'} // 0;
                            $covidTotalCases+= $covidAfterEffects;
                            $allOthersTotalCases+= $otherVaccinesAfterEffects;
                            $covidPlusOthersTotalCases+= $covidPlusOtherVaccinesAfterEffects;
                            for my $substanceName (sort keys %{$stats{'drugsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}}) {
                                my $eventsReported = $stats{'drugsCategorized'}->{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$substanceName} // die;
                                $substancesFetched{$substanceName} += $eventsReported;
                            }
                        }
                    }
                }
            }
        }
    }
    # p%substancesFetched;

    # Preparing substancesFetched for front rendering.
    my %substancesByNames = ();
    for my $substanceName (sort keys %substancesFetched) {
        my $eventsReported = $substancesFetched{$substanceName} // die;
        my ($substanceCategory, $substanceShortenedName) = substance_synthesis($substanceName, $eventsReported);
        next unless $substanceCategory;
        $substancesByNames{$substanceShortenedName}->{'substanceCategory'} = $substanceCategory;
        $substancesByNames{$substanceShortenedName}->{'eventsReported'} += $eventsReported;
    }
    my %substances = ();
    for my $substanceName (sort keys %substancesByNames) {
        if ($substanceName =~ /COVID-19/) {
            $covidTotalDrugs++;
        } else {
            $allOthersTotalDrugs++;
        }
        my $substanceCategory = $substancesByNames{$substanceName}->{'substanceCategory'} // die;
        my $reference;
        if ($substanceCategory eq 'COVID-19') {
            $reference = $covidTotalCases;
        } else {
            $reference = $allOthersTotalCases;
        }
        my $eventsReported    = $substancesByNames{$substanceName}->{'eventsReported'}    // die;
        my $percentOfTotal = nearest(1, $eventsReported * 100 / $reference);
        $percentOfTotal = 1 if $percentOfTotal < 1;
        $substances{$substanceCategory}->{$eventsReported}->{'percentOfTotal'} = $percentOfTotal;
        $substances{$substanceCategory}->{$eventsReported}->{'substances'}->{$substanceName} = 1;
    }
    p%substances;

    $self->render(
        covidTotalCases           => $covidTotalCases,
        covidTotalDrugs           => $covidTotalDrugs,
        allOthersTotalCases       => $allOthersTotalCases,
        allOthersTotalDrugs       => $allOthersTotalDrugs,
        covidPlusOthersTotalCases => $covidPlusOthersTotalCases,
        fetchedStat               => $fetchedStat,
        currentLanguage           => $currentLanguage,
        fromAge                   => $fromAge,
        toAge                     => $toAge,
        fromYear                  => $fromYear,
        toYear                    => $toYear,
        reporter                  => $reporter,
        sexGroup                  => $sexGroup,
        fromAges                  => \%fromAges,
        toAges                    => \%toAges,
        fromYears                 => \%fromYears,
        toYears                   => \%toYears,
        sexGroups                 => \%sexGroups,
        reporters                 => \%reporters,
        fetchedStats              => \%fetchedStats,
        languages                 => \%languages,
        substances                => \%substances
    );
}
# Diphtérie, Tétanos, Hépatithe B, Polyomélite

sub substance_synthesis {
    my ($substanceName, $eventsReported) = @_;
    return 0 if
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLULAVAL QUADRIVALENT)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - RV1 - ROTAVIRUS (ROTARIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - MENB - MENINGOCOCCAL B (BEXSERO)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HIBV - HIB (PEDVAXHIB)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - MNQ - MENINGOCOCCAL CONJUGATE (MENVEO)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HIBV - HIB (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTOX - DIPHTHERIA TOXOIDS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUA3 - INFLUENZA (SEASONAL) (FLUAD)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - RVX - ROTAVIRUS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - RV5 - ROTAVIRUS (ROTATEQ)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - VARCEL - VARICELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE QUADRIVALENT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - PPV - PNEUMO (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - VARCEL - VARICELLA (VARIVAX)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HEPA - HEP A (VAQTA)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE HIGH-DOSE)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - PPV - PNEUMO (PNEUMOVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - BCG - BCG (MYCOBAX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLULAVAL)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (QIV DRESDEN)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU3 - INFLUENZA (SEASONAL) (FLUARIX)' ||
        $substanceName eq 'CDC - PROTEIN SCIENCES CORPORATION - FLUR4 - INFLUENZA (SEASONAL) (FLUBLOK QUADRIVALENT)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - UNK - VACCINE NOT SPECIFIED (OTHER)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - MENB - MENINGOCOCCAL B (TRUMENBA)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMRV - MEASLES + MUMPS + RUBELLA + VARICELLA (PROQUAD)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - MMR - MEASLES + MUMPS + RUBELLA (MMR II)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLUC4 - INFLUENZA (SEASONAL) (FLUCELVAX QUADRIVALENT)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HPV9 - HPV (GARDASIL 9)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - VARZOS - ZOSTER (SHINGRIX)' ||
        $substanceName eq 'CDC - PAXVAX - CHOL - CHOLERA (VAXCHORA)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MU - MUMPS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - VARZOS - ZOSTER (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - HIBV - HIB (ACTHIB)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC - PNEUMO (PREVNAR)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TYP - TYPHOID VI POLYSACCHARIDE (TYPHIM VI)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - VARZOS - ZOSTER LIVE (ZOSTAVAX)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC13 - PNEUMO (PREVNAR13)' ||
        $substanceName eq 'ECDC - DIPHTHERIA ANTITOXIN' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU3 - INFLUENZA (SEASONAL) (FLUZONE)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HPV4 - HPV (GARDASIL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - RUB - RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MEN - MENINGOCOCCAL (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLUA4 - INFLUENZA (SEASONAL) (FLUAD QUADRIVALENT)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - PNC20 - PNEUMO (PREVNAR20)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - DTAP - DTAP (INFANRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - SMALL - SMALLPOX (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - JEVX - JAPANESE ENCEPHALITIS (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - YF - YELLOW FEVER (YF-VAX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HPVX - HPV (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TTOX - TETANUS TOXOID, ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN4 - INFLUENZA (SEASONAL) (FLUMIST QUADRIVALENT)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - RAB - RABIES (RABAVERT)' ||
        $substanceName eq 'CDC - NOVARTIS VACCINES AND DIAGNOSTICS - FLUC3 - INFLUENZA (SEASONAL) (FLUCELVAX)' ||
        $substanceName eq 'CDC - BERNA BIOTECH, LTD. - TYP - TYPHOID LIVE ORAL TY21A (VIVOTIF)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - VARCEL - VARICELLA (VARILRIX)' ||
        $substanceName eq 'CDC - INTERCELL AG - JEV1 - JAPANESE ENCEPHALITIS (IXIARO)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - FLUX(H1N1) - INFLUENZA (H1N1) (H1N1 (MONOVALENT) (UNKNOWN))' ||
        $substanceName eq 'CDC - MEDIMMUNE VACCINES, INC. - FLUN3 - INFLUENZA (SEASONAL) (FLUMIST)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEPA - HEP A (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEPA - HEP A (HAVRIX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENACTRA)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - YF - YELLOW FEVER (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - MMR - MEASLES + MUMPS + RUBELLA (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - FLUX - INFLUENZA (SEASONAL) (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MEN - MENINGOCOCCAL (MENOMUNE)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - MNQ - MENINGOCOCCAL CONJUGATE (MENQUADFI)' ||
        $substanceName eq 'CDC - SEQIRUS, INC. - FLU4 - INFLUENZA (SEASONAL) (AFLURIA QUADRIVALENT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - SMALL - SMALLPOX (ACAM2000)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - FLU4 - INFLUENZA (SEASONAL) (FLUZONE QUADRIVALENT)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - FLU4 - INFLUENZA (SEASONAL) (FLUARIX QUADRIVALENT)';
    my $substanceShortenedName;
    if (
        $substanceName eq 'ECDC - HEPATITIS B VACCINE (RDNA)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HIBV - HIB (HIBERIX)' ||
        $substanceName eq 'ECDC - HAEMOPHILUS INFLUENZAE TYPE B (NEISSERIA MENINGITIDIS OUTER MEMBRANE PROTEIN COMPLEX CONJUGATE) AND HEPATITIS B (RECOMBI'
    ) {
        $substanceShortenedName = 'HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'CDC - SANOFI PASTEUR - DT - DT ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'ECDC - DIPHTHERIA VACCINE (ADSORBED)' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA VACCINE';
    } elsif (
        $substanceName eq 'ECDC - POLIOMYELITIS VACCINE (INACTIVATED)' ||
        $substanceName eq 'CDC - PASTEUR MERIEUX CONNAUGHT - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - PFIZER\WYETH - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (IPOL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - IPV - POLIO VIRUS, INACT. (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - IPV - POLIO VIRUS, INACT. (POLIOVAX)'
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (IPV) VACCINE';
    } elsif (
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - OPV - POLIO VIRUS, ORAL (NO BRAND NAME)' ||
        $substanceName eq '' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'POLIOMYELITIS (OPV) VACCINE';
    } elsif (
        $substanceName eq 'ECDC - TETANUS VACCINES' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TTOX - TETANUS TOXOID (NO BRAND NAME)' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'TETANUS VACCINE';
    } elsif (
        $substanceName eq 'CDC - MERCK & CO. INC. - HBHEPB - HIB + HEP B (COMVAX)' ||
        $substanceName eq '' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'HAEMOPHILIUS B & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEPAB - HEP A + HEP B (NO BRAND NAME)' ||
        $substanceName eq 'CDC - DYNAVAX TECHNOLOGIES CORPORATION - HEP - HEP B (HEPLISAV-B)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'CDC - MERCK & CO. INC. - HEP - HEP B (RECOMBIVAX HB)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - HEP - HEP B (NO BRAND NAME)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - HEPAB - HEP A + HEP B (TWINRIX)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - HEP - HEP B (ENGERIX-B)' ||
        $substanceName eq 'CDC - SMITHKLINE BEECHAM - HEPAB - HEP A + HEP B (TWINRIX)'
    ) {
        $substanceShortenedName = 'HEPATITE A & HEPATITE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS AND POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED, REDUCED ANTIGEN(S) CONTENT)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPV - DTAP + IPV (QUADRACEL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPIPV - DTAP + IPV (UNKNOWN)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA AND TETANUS VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - TDAP - TDAP (BOOSTRIX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TDAP - TDAP (ADACEL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TDAP - TDAP (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - MASS. PUB HLTH BIOL LAB - TD - TD ADSORBED (TDVAX)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TD - TD ADSORBED (TENIVAC)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - TD - TD ADSORBED (NO BRAND NAME)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - TD - TETANUS DIPHTHERIA (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA & TETANUS VACCINE';
    } elsif (
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAP - DTAP (DAPTACEL)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAP - DTAP (NO BRAND NAME)' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS AND PERTUSSIS (ACELLULAR, COMPONENT) VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAP - DTAP (INFANRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTP - DTP (NO BRAND NAME)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAP - DTAP (TRIPEDIA)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS & PERTUSSIS VACCINE';
    } elsif (
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (PENTACEL)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPHEPBIP - DTAP + HEPB + IPV (PEDIARIX)' ||
        $substanceName eq 'CDC - GLAXOSMITHKLINE BIOLOGICALS - DTAPIPV - DTAP + IPV (KINRIX)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTAPIPVHIB - DTAP + IPV + HIB (UNKNOWN)' ||
        $substanceName eq 'CDC - MSP VACCINE COMPANY - DTPPVHBHPB - DTAP+IPV+HIB+HEPB (VAXELIS)' ||
        $substanceName eq 'CDC - SANOFI PASTEUR - DTAPIPVHIB - DTAP + IPV + HIB (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTERIA, TETANUS, WHOOPING COUGH, POLIOMYELITIS & HAEMOPHILIUS INFLUENZA TYPE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED)' ||
        $substanceName eq '' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), HEPATITIS B (RDNA), POLIOMYELITIS (INACT.) AND HAEMOPHILUS TYPE B' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), POLIOMYELITIS (INACTIVATED) AND HAEMOPHILUS TYPE B CONJUGATE VACC' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA) AND HAEMOPHILUS INFLUENZAE TYPE B CONJUGATE VACCINE (ADSORBED)' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND HAEMOPHILUS TYPE B CONJUGATE VACCINE (ADSORBED)' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA), POLIOMYELITIS & HAEMOPHILUS TYPE B VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT), HEPATITIS B (RDNA), POLIOMYELITIS (INACTIVATED) VACCINE (ADSORBED' ||
        $substanceName eq ''
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS, HEPATITIS B (RDNA) & POLIOMYELITIS VACCINE';
    } elsif (
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS (ACELLULAR, COMPONENT) AND HEPATITIS B (RDNA) VACCINE (ADSORBED)' ||
        $substanceName eq 'ECDC - DIPHTHERIA, TETANUS, PERTUSSIS AND HEPATITIS B (RDNA) VACCINE (ADSORBED)' ||
        $substanceName eq 'CDC - UNKNOWN MANUFACTURER - DTPHEP - DTP + HEP B (NO BRAND NAME)'
    ) {
        $substanceShortenedName = 'DIPHTHERIA, TETANUS, PERTUSSIS & HEPATITIS B (RDNA) VACCINE';
    } elsif (
        $substanceName eq 'CDC - JANSSEN - COVID19 - COVID19 (COVID19 (JANSSEN))' ||
        $substanceName eq 'ECDC - COVID-19 VACCINE JANSSEN (AD26.COV2.S)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE JANSSEN';
    } elsif (
        $substanceName eq 'CDC - MODERNA - COVID19 - COVID19 (COVID19 (MODERNA))' ||
        $substanceName eq 'ECDC - COVID-19 MRNA VACCINE MODERNA (CX-024414)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE MODERNA';
    } elsif (
        $substanceName eq 'CDC - PFIZER\BIONTECH - COVID19 - COVID19 (COVID19 (PFIZER-BIONTECH))' ||
        $substanceName eq 'ECDC - COVID-19 MRNA VACCINE PFIZER-BIONTECH (TOZINAMERAN)'
    ) {
        $substanceShortenedName = 'COVID-19 VACCINE PFIZER-BIONTECH';
    } elsif ($substanceName eq 'CDC - UNKNOWN MANUFACTURER - COVID19 - COVID19 (COVID19 (UNKNOWN))') {
        $substanceShortenedName = 'COVID-19 VACCINE UNKNOWN MANUFACTURER';
    } elsif ($substanceName eq 'ECDC - COVID-19 VACCINE ASTRAZENECA (CHADOX1 NCOV-19)') {
        $substanceShortenedName = 'COVID-19 VACCINE ASTRAZENECA';
    } elsif ($substanceName eq 'ECDC - COVID-19 VACCINE NOVAVAX (NVX-COV2373)') {
        $substanceShortenedName = 'COVID-19 VACCINE NOVAVAX';
    } else {
        die "substanceName : $substanceName, eventsReported : $eventsReported";
    }
    my $substanceCategory;
    if ($substanceShortenedName =~ /COVID-19/) {
        $substanceCategory = 'COVID-19';
    } else {
        $substanceCategory = 'Other Substances'
    }
    return ($substanceCategory, $substanceShortenedName);
}

sub contact_email {
    my $self = shift;
    my %json = ();
    my ($userEmail, $currentLanguage);
    my $json = $self->req->json;
    my $ipAddress = $self->remote_addr;
    if ($json) {
        # p$json;
        $userEmail = %$json{'userEmail'};
        $currentLanguage = %$json{'currentLanguage'} // 'fr';
    }


    my %response = ();
    if (!$userEmail || !$ipAddress) {
        if ($currentLanguage eq 'en') {
            $response{'status'} = 'Missing email address';
        } elsif ($currentLanguage eq 'fr') {
            $response{'status'} = 'Addresse courriel manquante';
        } else {

        }
    } else {
        # Verify if the mail format is valid.
        unless( Email::Valid->address($userEmail) ) {
            if ($currentLanguage eq 'en') {
                $response{'status'} = 'Please verify your email format';
            } elsif ($currentLanguage eq 'fr') {
                $response{'status'} = 'Veuillez vérifier le format de votre addresse courriel';
            } else {

            }
        } else {

            # Verifies if the email is already known.
            my $sTb = $self->dbh->selectrow_hashref("SELECT id as sessionId FROM session WHERE ipAddress = ?", undef, $ipAddress);
            unless ($sTb) {
                if ($currentLanguage eq 'en') {
                    $response{'status'} = 'Please verify that Javascript is enabled & verify that your browser is up to date';
                } elsif ($currentLanguage eq 'fr') {
                    $response{'status'} = 'Veuillez vérifier que vous avez activé Javascript & que votre navigateur est à jour';
                } else {

                }
            } else {
                $response{'status'} = 'ok';
                my $sessionId = %$sTb{'sessionId'} // die;
                my $eTb = $self->dbh->selectrow_hashref("SELECT id FROM email WHERE sessionId = $sessionId AND email = ?", undef, $userEmail);
                unless ($eTb) {
                    my $sth = $self->dbh->prepare("INSERT INTO email (sessionId, email) VALUES (?, ?)");
                    $sth->execute($sessionId, $userEmail) or die $sth->err();
                }
            }
        }
    }


    $self->render(
        json => \%response
    );
}

1;
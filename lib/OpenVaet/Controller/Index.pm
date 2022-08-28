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
    my $targetSource    = $self->param('targetSource')    // 'na';
    my $fetchedStat     = $self->param('fetchedStat')     // 'deaths';
    my $fromYear        = $self->param('fromYear')        // '2020';
    my $toYear          = $self->param('toYear')          // '2022';
    my $fromAge         = $self->param('fromAge')         // '0m';
    my $toAge           = $self->param('toAge')           // '64y';
    my $reporter        = $self->param('reporter')        // 'na';
    my $sexGroup        = $self->param('sexGroup')        // 'na';

    my %languages = ();
    $languages{'fr'} = 'Français';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage           => $currentLanguage,
        fetchedStat               => $fetchedStat,
        targetSource              => $targetSource,
        fromAge                   => $fromAge,
        toAge                     => $toAge,
        fromYear                  => $fromYear,
        toYear                    => $toYear,
        reporter                  => $reporter,
        sexGroup                  => $sexGroup,
        languages                 => \%languages
    );
}

sub index_content {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $targetSource    = $self->param('targetSource')    // die;
    my $fetchedStat     = $self->param('fetchedStat')     // die;
    my $fromYear        = $self->param('fromYear')        // die;
    my $toYear          = $self->param('toYear')          // die;
    my $fromAge         = $self->param('fromAge')         // die;
    my $toAge           = $self->param('toAge')           // die;
    my $reporter        = $self->param('reporter')        // die;
    my $sexGroup        = $self->param('sexGroup')        // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    # say "currentLanguage : [$currentLanguage]";
    # say "fetchedStat     : [$fetchedStat]";
    # say "fromAge         : [$fromAge]";
    # say "toAge           : [$toAge]";
    # say "reporter        : [$reporter]";
    # say "sexGroup        : [$sexGroup]";

    # Loggin session if unknown.
    session::session_from_self($self);
    # say "currentLanguage : [$currentLanguage]";
    # say "fetchedStat     : [$fetchedStat]";
    # say "fromAge         : [$fromAge]";
    # say "toAge           : [$toAge]";
    # say "reporter        : [$reporter]";
    # say "sexGroup        : [$sexGroup]";

    # Fetching user setting if user is logged.
    my $userId          = $self->session('userId');
    my $hasClosedDisclaimer = 0;
    if ($userId) {
        my $tb = $self->dbh->selectrow_hashref("SELECT hasClosedDisclaimer FROM user WHERE id = $userId", undef);
        $hasClosedDisclaimer = %$tb{'hasClosedDisclaimer'} // die;
        $hasClosedDisclaimer = unpack("N", pack("B32", substr("0" x 32 . $hasClosedDisclaimer, -32)));
    }

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

    my %sources = ();
    $sources{'1'}->{'value'} = 'na';
    $sources{'2'}->{'value'} = 1;
    $sources{'3'}->{'value'} = 2;
    $sources{'1'}->{'label'} = 'VAERS + EudraVigilance';
    $sources{'2'}->{'label'} = 'EudraVigilance';
    $sources{'3'}->{'label'} = 'VAERS';

    my $covidTotalCases           = 0;
    my $covidPlusOthersTotalCases = 0;
    my $allOthersTotalCases       = 0;
    my $covidTotalDrugs           = 0;
    my $allOthersTotalDrugs       = 0;
    my $eventStats                = "stats/events_stats.json";
    if (-f $eventStats) {
        my $json;
        open my $in, '<:utf8', $eventStats;
        while (<$in>) {
            $json .= $_;
        }
        close $in;
        my $eventStats = decode_json($json);
        my %eventStats = %$eventStats;
        if (exists $eventStats{$fetchedStat}) {
            for my $yearName (sort{$a <=> $b} keys %{$eventStats{$fetchedStat}}) {
                if ($fromYear ne 'na') {
                    next if $fromYear > $yearName;
                }
                next if $toYear  < $yearName;
                for my $reporterTypeName (sort keys %{$eventStats{$fetchedStat}->{$yearName}}) {
                    if ($reporter ne 'na') {
                        if ($reporter eq 'md') {
                            next if $reporterTypeName ne 'Healthcare Professional';
                        } elsif ($reporter eq 'nmd') {
                            next if $reporterTypeName eq 'Healthcare Professional';
                        } else {
                            die "reporter : $reporter";
                        }
                    }
                    for my $ageGroupName (sort keys %{$eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}}) {
                        if ($fromAge ne '0m' || $toAge ne '86y') {
                            next if $ageGroupName eq 'Not Specified';
                        }
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
                        for my $sexName (sort keys %{$eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}}) {
                            if ($sexGroup ne 'na') {
                                if ($sexGroup eq 'm') {
                                    next if $sexName ne 'Male';
                                } elsif ($sexGroup eq 'f') {
                                    next if $sexName ne 'Female';
                                } else {
                                    die "sexGroup : $sexGroup";
                                }
                            }
                            for my $sourceId (sort keys %{$eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}}) {
                                if ($targetSource ne 'na') {
                                    next unless $sourceId == $targetSource;
                                }
                                my $covidAfterEffects                  = $eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}->{'COVID19'}       // 0;
                                my $otherVaccinesAfterEffects          = $eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}->{'OTHER'}         // 0;
                                my $covidPlusOtherVaccinesAfterEffects = $eventStats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}->{'COVID19+OTHER'} // 0;
                                $covidTotalCases           += $covidAfterEffects;
                                $allOthersTotalCases       += $otherVaccinesAfterEffects;
                                $covidPlusOthersTotalCases += $covidPlusOtherVaccinesAfterEffects;
                                # say "$yearName - $reporterTypeName - $ageGroupName - $sexName - $covidAfterEffects - $otherVaccinesAfterEffects - $covidPlusOtherVaccinesAfterEffects";
                                # say "--> $covidTotalCases - $allOthersTotalCases - $covidPlusOthersTotalCases";
                            }
                        }
                    }
                }
            }
        }
    }

    $self->render(
        mainHeight                => $mainHeight,
        mainWidth                 => $mainWidth,
        currentLanguage           => $currentLanguage,
        hasClosedDisclaimer       => $hasClosedDisclaimer,
        covidTotalCases           => $covidTotalCases,
        covidTotalDrugs           => $covidTotalDrugs,
        allOthersTotalCases       => $allOthersTotalCases,
        allOthersTotalDrugs       => $allOthersTotalDrugs,
        covidPlusOthersTotalCases => $covidPlusOthersTotalCases,
        fetchedStat               => $fetchedStat,
        targetSource              => $targetSource,
        fromAge                   => $fromAge,
        toAge                     => $toAge,
        fromYear                  => $fromYear,
        toYear                    => $toYear,
        reporter                  => $reporter,
        sexGroup                  => $sexGroup,
        sources                   => \%sources,
        fromAges                  => \%fromAges,
        toAges                    => \%toAges,
        fromYears                 => \%fromYears,
        toYears                   => \%toYears,
        sexGroups                 => \%sexGroups,
        reporters                 => \%reporters,
        fetchedStats              => \%fetchedStats,
        languages                 => \%languages
    );
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

sub events_by_substances {
    my $self = shift;
    my $currentLanguage     = $self->param('currentLanguage')     // 'fr';
    my $targetSource        = $self->param('targetSource')        // 'na';
    my $fetchedStat         = $self->param('fetchedStat')         // 'deaths';
    my $fromYear            = $self->param('fromYear')            // '2020';
    my $toYear              = $self->param('toYear')              // '2022';
    my $fromAge             = $self->param('fromAge')             // '0m';
    my $toAge               = $self->param('toAge')               // '64y';
    my $reporter            = $self->param('reporter')            // 'na';
    my $sexGroup            = $self->param('sexGroup')            // 'na';
    my $covidTotalDrugs     = $self->param('covidTotalDrugs')     // 1;
    my $allOthersTotalDrugs = $self->param('allOthersTotalDrugs') // 1;
    my $covidTotalCases     = $self->param('covidTotalCases')     // 1;
    my $allOthersTotalCases = $self->param('allOthersTotalCases') // 1;
    # say "currentLanguage : [$currentLanguage]";
    # say "fetchedStat     : [$fetchedStat]";
    # say "fromAge         : [$fromAge]";
    # say "toAge           : [$toAge]";
    # say "reporter        : [$reporter]";
    # say "sexGroup        : [$sexGroup]";
    my $substancesStatsFile       = "stats/substance_stats.json";
    my %substancesFetched         = ();
    if (-f $substancesStatsFile) {
        my $json;
        open my $in, '<:utf8', $substancesStatsFile;
        while (<$in>) {
            $json .= $_;
        }
        close $in;
        my $stats = decode_json($json);
        my %stats = %$stats;
        if (exists $stats{$fetchedStat}) {
            for my $yearName (sort{$a <=> $b} keys %{$stats{$fetchedStat}}) {
                if ($fromYear ne 'na') {
                    next if $fromYear > $yearName;
                }
                next if $toYear  < $yearName;
                for my $reporterTypeName (sort keys %{$stats{$fetchedStat}->{$yearName}}) {
                    if ($reporter ne 'na') {
                        if ($reporter eq 'md') {
                            next if $reporterTypeName ne 'Healthcare Professional';
                        } elsif ($reporter eq 'nmd') {
                            next if $reporterTypeName eq 'Healthcare Professional';
                        } else {
                            die "reporter : $reporter";
                        }
                    }
                    for my $ageGroupName (sort keys %{$stats{$fetchedStat}->{$yearName}->{$reporterTypeName}}) {
                        if ($fromAge ne '0m' || $toAge ne '86y') {
                            next if $ageGroupName eq 'Not Specified';
                        }
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
                        for my $sexName (sort keys %{$stats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}}) {
                            if ($sexGroup ne 'na') {
                                if ($sexGroup eq 'm') {
                                    next if $sexName ne 'Male';
                                } elsif ($sexGroup eq 'f') {
                                    next if $sexName ne 'Female';
                                } else {
                                    die "sexGroup : $sexGroup";
                                }
                            }
                            for my $sourceId (sort keys %{$stats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}}) {
                                if ($targetSource ne 'na') {
                                    next unless $sourceId == $targetSource;
                                }
                                for my $substanceCategory (sort keys %{$stats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}}) {
                                    for my $substanceName (sort keys %{$stats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}->{$substanceCategory}}) {
                                        my $eventsReported = $stats{$fetchedStat}->{$yearName}->{$reporterTypeName}->{$ageGroupName}->{$sexName}->{$sourceId}->{$substanceCategory}->{$substanceName} // die;
                                        $substancesFetched{$substanceCategory}->{$substanceName} += $eventsReported;
                                    }
                                }
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
    for my $substanceCategory (sort keys %substancesFetched) {
        for my $substanceName (sort keys %{$substancesFetched{$substanceCategory}}) {
            my $eventsReported = $substancesFetched{$substanceCategory}->{$substanceName} // die;
            $substancesByNames{$substanceName}->{'substanceCategory'} = $substanceCategory;
            $substancesByNames{$substanceName}->{'eventsReported'} += $eventsReported;
        }
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

    $self->render(
        currentLanguage => $currentLanguage,
        targetSource => $targetSource,
        fetchedStat => $fetchedStat,
        fromYear => $fromYear,
        toYear => $toYear,
        fromAge => $fromAge,
        toAge => $toAge,
        reporter => $reporter,
        sexGroup => $sexGroup,
        substances => \%substances
    );
}

sub events_details {
    my $self = shift;
    my $substanceShortName = $self->param('substanceShortName');
    my $substanceCategory  = $self->param('substanceCategory');
    my $currentLanguage    = $self->param('currentLanguage');
    my $pageNumber         = $self->param('pageNumber');
    my $targetSource       = $self->param('targetSource');
    my $fetchedStat        = $self->param('fetchedStat');
    my $reporter           = $self->param('reporter');
    my $sexGroup           = $self->param('sexGroup');
    my $fromYear           = $self->param('fromYear');
    my $toYear             = $self->param('toYear');
    my $fromAge            = $self->param('fromAge');
    my $toAge              = $self->param('toAge');
    # say "
    #     substanceShortName  : $substanceShortName,
    #     substanceCategory   : $substanceCategory,
    #     currentLanguage     : $currentLanguage,
    #     pageNumber          : $pageNumber,
    #     fetchedStat         : $fetchedStat,
    #     reporter            : $reporter,
    #     sexGroup            : $sexGroup,
    #     fromAge             : $fromAge,
    #     toAge               : $toAge,
    #     fromYear            : $fromYear,
    #     toYear              : $toYear
    # ";

    # Fetching corresponding events.
    my $totalReports = 0;
    my $toEntry      = $pageNumber * 50;
    my $fromEntry    = $toEntry - 49;
    my @reports      = ();
    # say "folder : [stats/*/*/$substanceCategory/$fetchedStat.json]";
    # open my $out, '>:utf8', "$fetchedStat" . "_$fromYear" . "_$toYear" . "_$fromAge" . "_$toAge" . "_$reporter" . "_$sexGroup.csv";
    # say $out "Source;Reference;Sexe;Groupe Age;Age (Si CDC & Connu);Substance;Symptomes;Description (Si CDC & Connu);";
    for my $yearFile (glob "stats/*/*/$substanceCategory/$fetchedStat.json") {
        # say "yearFile : $yearFile";
        my ($yearName) = $yearFile =~ /stats\/(.*)\/.*\/$substanceCategory\/$fetchedStat\.json/;
        if ($fromYear ne 'na') {
            next if $fromYear > $yearName;
        }
        next if $toYear  < $yearName;
        # say "yearName : $yearName";
        open my $in, '<:utf8', $yearFile;
        my $json;
        while (<$in>) {
            $json = $_;
        }
        close $in;
        $json = decode_json($json);
        my $stats = shift @$json;
        my @stats = @$stats;
        for my $reportData (@stats) {
            # p$reportData;
            my $ageGroupName     = %$reportData{'ageGroupName'}     // die;
            my $reporterTypeName = %$reportData{'reporterTypeName'} // die;
            my $patientAge       = %$reportData{'patientAge'};
            my $description      = %$reportData{'description'};
            my $sourceId         = %$reportData{'sourceId'}         // die;
            my $sexName          = %$reportData{'sexName'}          // die;
            # say "ageGroupName     : $ageGroupName";
            # say "patientAge       : $patientAge";
            # say "sexName          : $sexName";
            # say "reporterTypeName : $reporterTypeName";
            # die;
            if ($fromAge ne '0m' || $toAge ne '86y') {
                next if $ageGroupName eq 'Not Specified';
            }
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
            if ($reporter ne 'na') {
                if ($reporter eq 'md') {
                    next if $reporterTypeName ne 'Healthcare Professional';
                } elsif ($reporter eq 'nmd') {
                    next if $reporterTypeName eq 'Healthcare Professional';
                } else {
                    die "reporter : $reporter";
                }
            }
            if ($sexGroup ne 'na') {
                if ($sexGroup eq 'm') {
                    next if $sexName ne 'Male';
                } elsif ($sexGroup eq 'f') {
                    next if $sexName ne 'Female';
                } else {
                    die "sexGroup : $sexGroup";
                }
            }
            if ($targetSource ne 'na') {
                next unless $sourceId == $targetSource;
            }
            # p$reportData;
            # last;
            # my $substanceString;
            my $hasSearch = 0;
            for my $substanceData (@{%$reportData{'substances'}}) {
                if ($substanceShortName) {
                    next unless %$substanceData{'substanceShortName'};
                    next unless %$substanceData{'substanceShortName'} eq $substanceShortName;
                    $hasSearch = 1;
                } else {
                    die unless $substanceCategory;
                    next unless %$substanceData{'substanceCategory'};
                    next unless %$substanceData{'substanceCategory'} eq $substanceCategory;
                    $hasSearch = 1;
                    # say "substanceCategory  : $substanceCategory";
                    # say "substanceShortName : $substanceShortName";
                }
                # $substanceString .= ", " . %$substanceData{'substanceShortName'} if $substanceString;
                # $substanceString  = %$substanceData{'substanceShortName'} if !$substanceString;
            }
            next unless $hasSearch == 1;

            # my $reactionsString;
            # for my $reactionData (@{%$reportData{'reactions'}}) {
            #     $reactionsString .= ", " . %$reactionData{'reactionName'} if $reactionsString;
            #     $reactionsString  = %$reactionData{'reactionName'} if !$reactionsString;
            # }
            my $source            = %$reportData{'source'}           // die;
            my $reference         = %$reportData{'reference'}        // die;
            my $receiptDate       = %$reportData{'receiptDate'}      // die;
            my $url               = %$reportData{'url'};
            # $description =~ s/;/, /g;
            # say $out "$source;$reference;$sexName;$ageGroupName;$patientAge;$substanceString;$reactionsString;$description;";
            $totalReports++;
            if ($totalReports >= $fromEntry && $totalReports <= $toEntry) {
                my %obj                  = ();
                $obj{'url'}              = $url;
                $obj{'source'}           = $source;
                $obj{'description'}      = $description;
                $obj{'reference'}        = $reference;
                $obj{'receiptDate'}      = $receiptDate;
                $obj{'ageGroupName'}     = $ageGroupName;
                $obj{'reporterTypeName'} = $reporterTypeName;
                $obj{'patientAge'}       = $patientAge;
                $obj{'sexName'}          = $sexName;
                for my $substanceData (@{%$reportData{'substances'}}) {
                    push @{$obj{'substances'}}, \%$substanceData;
                }
                for my $substanceData (@{%$reportData{'reactions'}}) {
                    push @{$obj{'reactions'}}, \%$substanceData;
                }
                # p%obj;
                push @reports, \%obj;
            }
        }
    }
    # close $out;
    my ($maxPages, %pages) = data_formatting::paginate($pageNumber, $totalReports, 50);
    # p%pages;

    $self->render(
        targetSource       => $targetSource,
        fetchedStat        => $fetchedStat,
        substanceCategory  => $substanceCategory,
        substanceShortName => $substanceShortName,
        currentLanguage    => $currentLanguage,
        fetchedStat        => $fetchedStat,
        fromYear           => $fromYear,
        toYear             => $toYear,
        fromAge            => $fromAge,
        toAge              => $toAge,
        reporter           => $reporter,
        sexGroup           => $sexGroup,
        pageNumber         => $pageNumber,
        maxPages           => $maxPages,
        totalReports       => $totalReports,
        pages              => \%pages,
        reports            => \@reports
    );
}

1;
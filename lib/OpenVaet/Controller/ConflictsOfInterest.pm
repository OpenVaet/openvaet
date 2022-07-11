package OpenVaet::Controller::ConflictsOfInterest;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub conflicts_of_interest {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages    = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub search_recipient {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $url = 'https://transparence.sante.gouv.fr/api/records/1.0/search/?disjunctive.beneficiaire_categorie=true&disjunctive.profession_libelle=' . 
              'true&disjunctive.ville=true&fields=identite,prenom,ville,ville_sanscedex,id_beneficiaire&sort=identite&q=%23search';
    my $searchInput = $self->param('searchInput');
    say "searchInput : [$searchInput]";
    say length $searchInput;
    my $errorMessage;
    my $totalRecipients = 0;
    my %recipients = ();
    if (length $searchInput < 1) {
        say "rending error ...";
        $errorMessage = 'Veuillez saisir votre recherche';
    } else {
        use HTTP::Cookies;
        use HTML::Tree;
        use LWP::UserAgent;
        use LWP::Simple;
        use HTTP::Cookies qw();
        use HTTP::Request::Common qw(POST OPTIONS);
        use HTTP::Headers;
        my @elems = split ' ', $searchInput;
        my $searchExtension;
        for my $elem (@elems) {
            $searchExtension .= '+AND+%23search(identite,prenom,ville,%27' . $elem . '%27)' if $searchExtension;
            $searchExtension = '(identite,prenom,ville,%27' . $elem . '%27)' if !$searchExtension;
        }
        $url = $url . $searchExtension;
        $url = $url . '&rows=20&dataset=beneficiaires&timezone=Europe%2FBerlin&lang=fr';
        say $url;

        my $ua                        = LWP::UserAgent->new
        (
            timeout                  => 30,
            cookie_jar               => HTTP::Cookies->new,
            agent                    => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
        );
        my $res     = $ua->get($url);
        my $content = $res->decoded_content;
        # say "content : $content";
        my $json    = decode_json($content);
        my %data = %$json;
        if (exists $data{'records'}) {
            for my $recordData (@{$data{'records'}}) {
                $totalRecipients++;
                my $recipientId = %$recordData{'fields'}->{'id_beneficiaire'} // die;
                my $lastName    = %$recordData{'fields'}->{'identite'}        // die;
                my $firstName   = %$recordData{'fields'}->{'prenom'}          // die;
                my $city        = %$recordData{'fields'}->{'ville'}           // die;
                $city =~ s/\|/, /g;
                $recipients{$recipientId}->{'lastName'}  = $lastName;
                $recipients{$recipientId}->{'firstName'} = $firstName;
                $recipients{$recipientId}->{'city'}      = $city;
                # p$recordData;
            }
        }
        # say $content;
        # p$json;
    }
    # p%recipients;

    $self->render(
        errorMessage    => $errorMessage,
        searchInput     => $searchInput,
        totalRecipients => $totalRecipients,
        recipients      => \%recipients
    );
}

sub confirm_recipients {
    my $self        = shift;
    my $searchInput = $self->param('searchInput') // die;
    my $resultsJson = $self->param('resultsJson') // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    use LWP::Simple;

    my $results = decode_json($resultsJson);
    my @results = @$results;

    # say "searchInput : $searchInput";
    # say "resultsJson : $resultsJson";
    # p$results;

    my $currentDate = time::current_datetime();
    ($currentDate)  = split ' ', $currentDate;
    my %statistics = ();
    $statistics{'latestCompdate'} = 0;

    for my $recipientId (@results) {
        my $url = 'https://sante-sgsocialgouv.opendatasoft.com/explore/dataset/declarations/download/?&sort=-date&refine.id_beneficiaire=' .
                    $recipientId . '&disjunctive.lien_interet=true&disjunctive.raison_sociale=true&q=&timezone=Europe/Berlin&lang=fr&' .
                    'use_labels_for_header=true&csv_separator=%3B';
        my $filename = "tsg-$recipientId-$currentDate.csv";
        unless (-f $filename) {
            my $rc = getstore($url, $filename);
            if (is_error($rc)) {
                die "getstore of <$url> failed with $rc";
            }
        }
        # say "url      : $url";
        # say "filename : $filename";

        # Loading data from file.
        open my $in, '<:utf8', $filename;
        my $lNum = 0;
        while (<$in>) {
            my (
                $transactionId,
                $transactionToken,
                $corporateId,
                $linkOfInterest,
                $uniqueIdentifier,
                $relatedConvention,
                $reasonForConflictOfInterest,
                $motiveForConflictOfInterest,
                $otherMotiveForConflictOfInterest,
                $eventInformation,
                $amount,
                $date,
                $dateFrom,
                $dateTo,
                $recipientId,
                $recipientLastName,
                $recipientFirstName,
                $recipientCategoryCode,
                $recipientCategory,
                $recipientTypeCode,
                $recipientType,
                $recipientIdentifier,
                $recipientProfessionCode,
                $labelledProfession,
                $exerciceStructure,
                $countryCode,
                $address,
                $postalCode,
                $city,
                $rectificationRequest,
                $status,
                $publicationDate,
                $transmissionDate,
                $donatorFullName,
                $activitySector,
                $corporateCity,
                $corporateDepartment,
                $corporateRegion,
                $corporateCountry,
                $motherCorporateId
            ) = split ';', $_;
            $lNum++;
            next if $lNum == 1;
            if (length $amount > 0) {
                my ($transactionYear) = split '-', $transmissionDate;
                my $transmissionCompdate = $transmissionDate;
                $transmissionCompdate =~ s/\D//g;
                $statistics{'transactions'}->{$transmissionCompdate}->{$transactionId}->{'amount'} = $amount;
                $statistics{'transactions'}->{$transmissionCompdate}->{$transactionId}->{'donatorFullName'} = $donatorFullName;
                $statistics{'transactions'}->{$transmissionCompdate}->{$transactionId}->{'transmissionDate'} = $transmissionDate;
                if ($transmissionCompdate > $statistics{'latestCompdate'}) {
                    $statistics{'latestCompdate'}         = $transmissionCompdate;
                    $statistics{'latestTransmissionDate'} = $transmissionDate;
                }
                my $recipientFullName = lc $recipientFirstName;
                $recipientFullName    = ucfirst $recipientFullName;
                $recipientLastName    = uc $recipientLastName;
                $recipientFullName    = "$recipientFullName $recipientLastName";
                $statistics{'totalSum'}->{'amount'} += $amount;
                $statistics{'totalSum'}->{'totalTransactions'}++;
                $statistics{'byYear'}->{$transactionYear}->{'amount'} += $amount;
                # $statistics{'byDonatorAndYear'}->{$donatorFullName}->{$transactionYear}->{'amount'} += $amount;
                $statistics{'byDonator'}->{$donatorFullName}->{'amount'} += $amount;
            }


        }
        close $in;

    }

    # Formatting numbers for output.
    use Number::Format;
    my $de = new Number::Format(-thousands_sep   => ' ',
                                -decimal_point   => '.');
    $statistics{'totalSum'}->{'amount'} = $de->format_number($statistics{'totalSum'}->{'amount'});
    my $totalYears    = 0;
    my $highestAmount = 0;
    for my $year (sort{$a <=> $b} keys %{$statistics{'byYear'}}) {
        my $amount = $statistics{'byYear'}->{$year}->{'amount'} // die;
        $highestAmount = $amount if $highestAmount < $amount;
        $totalYears++;
    }
    my $scale = 0;
    if ($highestAmount >= 0 && $highestAmount < 100) {
        $scale = 100;
    } elsif ($highestAmount >= 100 && $highestAmount < 500) {
        $scale = 500;
    } elsif ($highestAmount >= 500 && $highestAmount < 1000) {
        $scale = 1000;
    } elsif ($highestAmount >= 1000 && $highestAmount < 5000) {
        $scale = 5000;
    } elsif ($highestAmount >= 5000 && $highestAmount < 10000) {
        $scale = 10000;
    } elsif ($highestAmount >= 10000 && $highestAmount < 50000) {
        $scale = 50000;
    } elsif ($highestAmount >= 50000) {
        $scale = 100000;
    }
    my $highestAmountRounded = nearest($scale, $highestAmount);
    if ($highestAmountRounded < $highestAmount) {
        $highestAmountRounded += $scale;
    }
    for my $year (sort{$a <=> $b} keys %{$statistics{'byYear'}}) {
        $statistics{'byYear'}->{$year}->{'percentOfHighest'} = nearest(0.1, $statistics{'byYear'}->{$year}->{'amount'} * 100 / $highestAmountRounded);
        $statistics{'byYear'}->{$year}->{'amount'} = $de->format_number($statistics{'byYear'}->{$year}->{'amount'});
    }
    my $yearlyLineLength = $totalYears * 70;
    $yearlyLineLength   += 20;
    my $totalDonators    = 0;
    my $topDonators      = 5;
    for my $donatorFullName (sort keys %{$statistics{'byDonator'}}) {
        my $amount = $statistics{'byDonator'}->{$donatorFullName}->{'amount'} // die;
        my $amountFormatted = $de->format_number($amount);
        $statistics{'byDonatorAmount'}->{$amount}->{$donatorFullName}->{'amountFormatted'} = $amountFormatted;
        $totalDonators++;
    }
    $topDonators          = $totalDonators if $totalDonators < $topDonators;
    my $topDonatorsAmount = 0;
    my $loadedDonators    = 0;
    for my $amount (sort{$b <=> $a} keys %{$statistics{'byDonatorAmount'}}) {
        for my $donatorFullName (sort keys %{$statistics{'byDonatorAmount'}->{$amount}}) {
            $loadedDonators++;
            $topDonatorsAmount += $amount;
            last if $loadedDonators == $topDonators;
        }
        last if $loadedDonators == $topDonators;
    }

    delete $statistics{'byDonator'};

    # p%statistics;
    # say "highestAmountRounded : $highestAmountRounded";

    $self->render(
        topDonators          => $topDonators,
        topDonatorsAmount    => $topDonatorsAmount,
        totalDonators        => $totalDonators,
        highestAmountRounded => $highestAmountRounded,
        yearlyLineLength     => $yearlyLineLength,
        searchInput          => $searchInput,
        statistics           => \%statistics
    );
}

1;
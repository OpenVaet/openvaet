package OpenVaet::Controller::PfizerTrialCasesMapping;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub pfizer_trial_cases_mapping {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $merge4444To1231 = $self->param('merge4444To1231') // 1;

    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';

    my $json;
    open my $in, '<:utf8', 'public/doc/pfizer_trial_cases_mapping/stats_by_sites.json';
    while (<$in>) {
    	$json .= $_;
    }
    close $in;
    $json = decode_json($json);
    my %sites = ();
    for my $siteCode (sort{$a <=> $b} keys %{%$json{'By Sites Codes'}}) {
    	next unless %$json{'By Sites Codes'}->{$siteCode}->{'latitude'};
    	my $siteName   = %$json{'By Sites Codes'}->{$siteCode}->{'siteName'}   // die;
    	my $postalCode = %$json{'By Sites Codes'}->{$siteCode}->{'postalCode'} // die;
    	my $totalCases = %$json{'By Sites Codes'}->{$siteCode}->{'totalCases'} // die;
    	$sites{$totalCases}->{$siteCode}->{'siteName'} = $siteName;
    	$sites{$totalCases}->{$siteCode}->{'postalCode'} = $postalCode;
    }
    # p%sites;

    $self->render(
        currentLanguage => $currentLanguage,
        merge4444To1231 => $merge4444To1231,
        languages       => \%languages,
        sites           => \%sites
    );
}

sub load_pfizer_trial_cases_mapping {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    my $merge4444To1231 = $self->param('merge4444To1231') // die;

    say "siteTarget : $siteTarget";
    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";
    my $json;
    open my $in, '<:utf8', 'public/doc/pfizer_trial_cases_mapping/stats_by_sites.json';
    while (<$in>) {
    	$json .= $_;
    }
    close $in;
    $json = decode_json($json);
    my %sites = ();
    my ($targetLatitude, $targetLongitude, $targetTotalCases, $targetTotalCases);
    for my $siteCode (sort{$a <=> $b} keys %{%$json{'By Sites Codes'}}) {
    	next unless %$json{'By Sites Codes'}->{$siteCode}->{'latitude'};
    	if ($siteTarget) {
    		next unless $siteCode eq $siteTarget;
    	}
    	my $siteName   = %$json{'By Sites Codes'}->{$siteCode}->{'siteName'}   // die;
    	my $postalCode = %$json{'By Sites Codes'}->{$siteCode}->{'postalCode'} // die;
    	my $totalCases = %$json{'By Sites Codes'}->{$siteCode}->{'totalCases'} // die;
    	my $latitude = %$json{'By Sites Codes'}->{$siteCode}->{'latitude'} // die;
    	my $longitude = %$json{'By Sites Codes'}->{$siteCode}->{'longitude'} // die;
    	my $investigator = %$json{'By Sites Codes'}->{$siteCode}->{'investigator'} // die;
    	my $address = %$json{'By Sites Codes'}->{$siteCode}->{'address'} // die;
    	my $city = %$json{'By Sites Codes'}->{$siteCode}->{'city'} // die;
    	$sites{$siteCode}->{'siteName'}   = $siteName;
        if ($merge4444To1231 == 1) {
            if ($siteCode eq '1231') {
                $totalCases += %$json{'By Sites Codes'}->{'4444'}->{'totalCases'};
            }
        }
        $sites{$siteCode}->{'totalCases'} = $totalCases;
    	$sites{$siteCode}->{'postalCode'} = $postalCode;
    	$sites{$siteCode}->{'address'} = $address;
    	$sites{$siteCode}->{'city'} = $city;
    	$sites{$siteCode}->{'investigator'} = $investigator;
    	$sites{$siteCode}->{'latitude'} = $latitude;
    	$sites{$siteCode}->{'longitude'} = $longitude;
    }

    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        languages       => \%languages,
        sites           => \%sites
    );
}

1;
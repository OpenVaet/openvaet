package OpenVaet;
use Mojo::Base 'Mojolicious';
use DBI;
use JSON;
use Mojolicious::Static;
use Mojo::IOLoop;
use Cwd;
use Data::Printer;
# use Digest::MD5 qw(md5_hex);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use config;

# This method will run once at server start
sub startup {
	my $self = shift;
    $self->plugin('Config');
    $self->config(
        hypnotoad => {
            listen => ['https://*:8082']
        },
    );

    # load and configure CORS
    $self->plugin('SecureCORS');
    $self->plugin('SecureCORS', { max_age => undef });
    $self->plugin('RemoteAddr');

    # set app-wide CORS defaults
    $self->hook(
        before_dispatch => sub {
            my $c = shift;
            $c->res->headers->header('Access-Control-Allow-Origin' => '*');
            $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
            $c->res->headers->access_control_allow_origin('*');
            my $forwardBase = $c->req->headers->header('X-Forwarded-Base');
            $c->req->url->base(Mojo::URL->new($forwardBase)) if $forwardBase;
        }
    );
    $self->hook(
        after_dispatch => sub { 
            my $c        = shift;
            my $referrer = $c->req->headers->referrer || '';
            my $method   = $c->req->method || '';
            if ($method eq 'OPTIONS') {
                $c->res->headers->header('Access-Control-Allow-Origin' => '*'); 
                $c->res->headers->access_control_allow_origin('*');
                $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
                $c->res->headers->header('Access-Control-Allow-Headers' => 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
                $c->respond_to(any => { data => '', status => 200 });
            }
        }
    );

    # Load configuration from hash returned by config file
    my $config = \%config;
    $self->helper(config => sub {return $config});
    $self->plugin('RemoteAddr');

	# Configure the application
	$self->secrets($config->{'secrets'});

    # Data DB handler
    my $dbh;
    $self->helper(dbh => sub {
        $dbh ||= connect_dbi($config);
        if (! $dbh->ping ) {
            $dbh = $dbh->clone();
        }
        return $dbh;
    });

	# Enums.
	$self->helper(enums => sub { return \%enums; } );

	# Router
	my $r = $self->routes;

	# Unprotected routes
	$r->get('/')->to('index#index');
	$r->post('/contact_email')->to('index#contact_email');
	$r->post('/index/events_by_substances')->to('index#events_by_substances');
	$r->post('/index/events_details')->to('index#events_details');
	$r->get('/disclaimer')->to('disclaimer#disclaimer');
	$r->get('/contact_us')->to('contact_us#contact_us');
	$r->post('/contact_us/send_contact_us')->to('contact_us#send_contact_us');
	$r->get('/data')->to('data#data');
	$r->get('/data/cdc')->to('cdc#cdc');
	$r->get('/data/cdc/state_year_reports')->to('cdc#state_year_reports');
	$r->post('/data/cdc/load_state_years')->to('cdc#load_state_years');
	$r->get('/data/cdc/notices')->to('cdc#notices');
	$r->post('/data/cdc/load_notices_filters')->to('cdc#load_notices_filters');
	$r->post('/data/cdc/load_notices')->to('cdc#load_notices');
	$r->get('/data/ecdc')->to('ecdc#ecdc');
	$r->get('/data/ecdc/substances')->to('ecdc#substances');
	$r->post('/data/ecdc/load_substances')->to('ecdc#load_substances');
	$r->post('/data/ecdc/set_ecdc_drug_indexation')->to('ecdc#set_ecdc_drug_indexation');
	$r->get('/data/ecdc/substance_details')->to('ecdc#substance_details');
	$r->get('/data/ecdc/notices')->to('ecdc#notices');
	$r->post('/data/ecdc/load_notices')->to('ecdc#load_notices');
	$r->post('/data/ecdc/load_notices_filters')->to('ecdc#load_notices_filters');
	$r->get('/data/data_gouv_fr')->to('data_gouv_fr#data_gouv_fr');
	$r->get('/data/oms')->to('oms#oms');
	$r->get('/changelog')->to('changelog#changelog');
	$r->get('/studies')->to('studies#studies');
    $r->get('/studies/vaers_fertility')->to('studies#vaers_fertility');
	$r->get('/studies/vaers_fertility/pregnancies_confirmation')->to('studies#pregnancies_confirmation');
	$r->post('/studies/vaers_fertility/load_pregnancy_confirmation')->to('studies#load_pregnancy_confirmation');
    $r->post('/studies/vaers_fertility/set_report_pregnancy_attribute')->to('studies#set_report_pregnancy_attribute');
    $r->get('/studies/vaers_fertility/pregnancies_arbitrations')->to('studies#pregnancies_arbitrations');
    $r->post('/studies/vaers_fertility/load_pregnancies_arbitrations_filters')->to('studies#load_pregnancies_arbitrations_filters');
    $r->post('/studies/vaers_fertility/load_pregnancies_arbitrations_reports')->to('studies#load_pregnancies_arbitrations_reports');
    $r->get('/studies/vaers_fertility/pregnancies_seriousness')->to('studies#pregnancies_seriousness');
    $r->post('/studies/vaers_fertility/load_pregnancy_seriousness_confirmation')->to('studies#load_pregnancy_seriousness_confirmation');
    $r->post('/studies/vaers_fertility/set_pregnancy_seriousness_attributes')->to('studies#set_pregnancy_seriousness_attributes');
    $r->post('/studies/vaers_fertility/symptoms')->to('studies#vaers_fertility_symptoms');
    $r->get('/studies/vaers_fertility/pregnancies_details')->to('studies#pregnancies_details');
    $r->post('/studies/vaers_fertility/load_pregnancies_details')->to('studies#load_pregnancies_details');
    $r->post('/studies/vaers_fertility/set_pregnancy_details_attributes')->to('studies#set_pregnancy_details_attributes');
    $r->post('/studies/vaers_fertility/display_reports')->to('studies#display_reports');
    $r->get('/studies/cdc_mortality')->to('cdc_mortality#cdc_mortality');
    $r->get('/studies/french_vaccines_watch')->to('french_vaccines_watch#french_vaccines_watch');
    $r->get('/conflicts_of_interest')->to('conflicts_of_interest#conflicts_of_interest');
    $r->post('/conflicts_of_interest/search_recipient')->to('conflicts_of_interest#search_recipient');
    $r->post('/conflicts_of_interest/confirm_recipients')->to('conflicts_of_interest#confirm_recipients');
    $r->get('/studies/french_insee_deathes_data')->to('french_insee_deathes_data#french_insee_deathes_data');
    $r->get('/pfizearch')->to('pfizearch#index');
    $r->get('/pfizearch/search')->to('pfizearch#search');
    $r->get('/pfizearch/documentation')->to('pfizearch#documentation');
    $r->get('/pfizearch/pdf_search_details')->to('pfizearch#pdf_search_details');
    $r->get('/pfizearch/viewer')->to('pfizearch#viewer');
    $r->post('/pfizearch/pdf_loader')->to('pfizearch#pdf_loader');
}

sub connect_dbi
{
    my ($config) = shift;
    return DBI->connect("DBI:mysql:database=" . $config->{databaseName} . ";" .
                        "host=" . $config->{databaseHost} . ";port=" . $config->{databasePort},
                        $config->{databaseUser}, $config->{databasePassword},
                        { PrintError => 1}) || die $DBI::errstr;
}

1;
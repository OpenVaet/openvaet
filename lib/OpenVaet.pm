package OpenVaet;
use Mojo::Base 'Mojolicious';
use Mojolicious::Plugin::Bcrypt;
use Mojolicious::Static;
use Mojo::IOLoop;
use DBI;
use JSON;
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

    # BCrypt passwords encryption.
    $self->plugin('bcrypt', { cost => 4 });

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

    # Users related functions.
    $self->helper(
        normalize_name => sub {
            my (undef, $name) = @_;
            return uc ($name || '');
        }
    );

    $self->helper(
        verify_password => sub {
            my (undef, $password) = @_;
            my $passwordLength = length $password;
            if ($passwordLength < 6) {
                return "invalidPasswordInput"
            } elsif ($passwordLength > 50) {
                return "invalidPasswordInput"
            } elsif ($password !~ /\d/) {
                return "invalidPasswordInput"
            } elsif ($password !~ /[a-zA-Z]/) {
                return "invalidPasswordInput"
            } elsif ($password =~ /[^a-zA-Z0-9\!\@\#\$\%\^\&\*\(\)\_\+]/) {
                return "invalidPasswordInput"
            }
            return "ok";
        }
    );

    # Returns 1 if the user is connected (session set and valid),
    # undef otherwise
    $self->helper(
        is_connected => sub {
            my $self          = shift;
            my $email         = $self->session("userMail") || return 0;
            my $token         = $self->session("token");

            return 0 unless $token;

            my $adminToken = $self->dbh->selectrow_hashref("SELECT token FROM user WHERE email = ?", undef, $email);
            return 0 unless %$adminToken{'token'};
            if (%$adminToken{'token'} eq $token) {
                return 1;
            } else {
                return 0;
            }
        }
    );

    # Returns 1 if the user is admin,
    # undef otherwise
    $self->helper(is_admin => sub {
        my $self          = shift;
        my $userId        = $self->session("userId");
        my $token         = $self->session("token");
        # say "tralala : [$name] - {$token}";

        return unless $userId && $token;

        my $uTb     = $self->dbh->selectrow_hashref("SELECT isAdmin, token FROM user WHERE id = ?", undef, $userId);
        return 0 unless $uTb;
        my $isAdmin = %$uTb{'isAdmin'} // die;
        $isAdmin    = unpack("N", pack("B32", substr("0" x 32 . $isAdmin, -32)));
        if ($isAdmin && %$uTb{'token'} eq $token) {
            return 1
        } else {
            return 0;
        }
    });

    # Token generator
    $self->helper(
        gen_token => sub {
            my @chars = ("a".."z","A".."Z",0..9);
            return join "", map { $chars[rand @chars] } 1 .. 64;
        }
    );

    # User logout.
    $self->helper(
        disconnect_user => sub {
            my ($self, $email, $token) = @_;
            my $userData = $self->dbh->selectrow_hashref(
                'SELECT * FROM user WHERE email = ?', undef, $email)
                || return { code => 2 };
            if ($userData->{token} ne $token) {
                return { code => 2 };
            }
            $self->dbh->do('UPDATE user SET token = NULL WHERE email = ?',
            undef, $email);
            $self->session(expires => 1);
            return {
                code => 0
            };
        }
    );

    # User login.
    $self->helper(
        connect_user => sub {
            my ($self, $email, $password) = @_;
            $email = $self->normalize_name($email);

            # Getting user data
            my $userData = $self->dbh->selectrow_hashref(
                'SELECT * FROM user WHERE email = ?', undef, $email)
                || return { code => 2 };

            # Testing if account is locked
            if ($userData->{lockoutUntilDatetime} && $userData->{lockoutUntilDatetime} > time) {
                say "failed with lock";
                return { code => 3 };
            }

            # Testing password
            if (!$self->bcrypt_validate( $password, $userData->{'password'})) {
                $self->dbh->do('UPDATE user SET failedAccessCount = failedAccessCount + 1 WHERE email = ?',
                undef, $email);
                # Testing if account needs to be locked
                my $failCount = $userData->{'failedAccessCount'};
                my $lockoutTime =
                    $failCount == 5 ? 60 * 5 :   # 5 minutes
                        $failCount == 10 ? 60 * 60 : # 1 hour
                            $failCount == 15 ? 60 * 60 * 24 : # 1 day
                                $failCount == 20 ? 60 * 60 * 24 * 365 : # 1 year
                                    $failCount >= 25 ? 60 * 60 * 24 * 365 * 1000 : # 1000 years
                0;
                if ($lockoutTime != 0) {
                    $self->dbh->do('UPDATE user SET lockoutUntilDatetime = ? WHERE email = ?',
                    undef, time() + $lockoutTime, $email);
                }
                return { code => 2 };
            }

            # Generating token and update DB with it
            my $sessionId = $self->gen_token();
            my $userId    = $userData->{'id'};
            my $emailVerification = $userData->{'emailVerification'};
            $emailVerification    = unpack("N", pack("B32", substr("0" x 32 . $emailVerification, -32)));
            $self->dbh->do('UPDATE user SET token = ?, failedAccessCount = 0, lastLoginTimestamp = UNIX_TIMESTAMP()
            WHERE email = ?',
            undef, $sessionId, $email);

            # Updating session
            $self->session->{emailVerification} = $emailVerification;
            $self->session->{userId}            = $userId;
            $self->session->{token}             = $sessionId;
            $self->session->{userMail}          = $email;

            # Returning token
            return { code => 0, token => $sessionId, emailVerification => $emailVerification };
        }
    );

    # Enums.
    $self->helper(enums => sub { return \%enums; } );

	# Router
	my $r = $self->routes;

    # Basic protection : just check if the user is connected.
    my $auth = $r->under(
        sub {
            my $self = shift;
            if ($self->is_connected()) {
                return 1;
            }
            # Setting referrer for redirection
            $self->session->{referrer} = $self->req->url->to_abs;
            # Setting error message
            # $self->flash(danger_alert_title => 'Accès protégé');
            # $self->flash(danger_alert => 'Veuillez vous connecter pour accéder à cette page.');
            # Redirecting to login page
            $self->redirect_to('/user_must_be_connected');
            return;
        }
    );

    # Enhanced protection : check if the user is connected & isAdmin.
    my $aAuth = $r->under(
        sub {
            my $self = shift;
            if ($self->is_admin()) {
                return 1;
            }
            # Setting referrer for redirection
            $self->session->{referrer} = $self->req->url->to_abs;
            # Setting error message
            # $self->flash(danger_alert_title => 'Accès protégé');
            # $self->flash(danger_alert => 'Veuillez vous connecter pour accéder à cette page.');
            # Redirecting to login page
            $self->redirect_to('/user_must_be_admin');
            return;
        }
    );

    ######################## Unprotected routes
    ### User Routes
    $r->post('/login/open_login_tab')->to('login#open_login_tab');
    $r->post('/login/do_login')->to('login#do_login');
    $r->post('/logout')->to('login#logout');

    ### Top Bar
    $r->post('/top_bar')->to('top_bar#top_bar');

    ### New user registration.
    $r->post('/new_user/create_user')->to('new_user#create_user');
    $r->post('/new_user/load_email_confirm')->to('new_user#load_email_confirm');
    $r->post('/new_user/confirm_email')->to('new_user#confirm_email');

    ### User account.
    $r->post('/user_account/forgot_password')->to('user_account#forgot_password');
    $r->post('/user_account/confirm_password_change')->to('user_account#confirm_password_change');

    ######################## Protected routes
    ### User account.
    $auth->post('/set_disclaimer_closing')->to('user_account#set_disclaimer_closing');
    $auth->get('/user_account/user_security')->to('user_account#user_security');
    $auth->post('/user_account/change_password')->to('user_account#change_password');

    ### Website browsing route (public).
	$r->get('/')->to('index#index');
    $r->post('/index/index_content')->to('index#index_content');
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
    $r->get('/twitter_thought_police')->to('twitter_thought_police#twitter_thought_police');
    $r->post('/twitter_thought_police/twitter_followed_users')->to('twitter_thought_police#twitter_followed_users');
    $r->post('/twitter_thought_police/twitter_banned_users')->to('twitter_thought_police#twitter_banned_users');
    $r->get('/twitter_thought_police/open_user_tweets')->to('twitter_thought_police#open_user_tweets');
    $r->post('/twitter_thought_police/twitter_banned_users_by_network')->to('twitter_thought_police#twitter_banned_users_by_network');
    $r->post('/twitter_thought_police/tag_username')->to('twitter_thought_police#tag_username');
    $r->get('/open_medic')->to('open_medic#open_medic');
    $r->get('/children_vaers')->to('children_vaers#children_vaers');
    $r->get('/covid_injections_facts_and_lies')->to('covid_injections_facts_and_lies#covid_injections_facts_and_lies');
    $r->get('/covid_injections_facts_and_lies/criticism_clinical_trials')->to('covid_injections_facts_and_lies#criticism_clinical_trials');
    $r->get('/covid_injections_facts_and_lies/clinical_trial_design_terminology')->to('covid_injections_facts_and_lies#clinical_trial_design_terminology');
    $r->get('/covid_injections_facts_and_lies/four_phases_of_clinical_trial')->to('covid_injections_facts_and_lies#four_phases_of_clinical_trial');
    $r->get('/covid_injections_facts_and_lies/pandemrix_vaccine')->to('covid_injections_facts_and_lies#pandemrix_vaccine');
    $r->get('/covid_injections_facts_and_lies/when_goes_wrong_thalidomide')->to('covid_injections_facts_and_lies#when_goes_wrong_thalidomide');
    $r->get('/covid_injections_facts_and_lies/clinical_trial_2020')->to('covid_injections_facts_and_lies#clinical_trial_2020');
    $r->get('/covid_injections_facts_and_lies/pcr_test_lft_limitations')->to('covid_injections_facts_and_lies#pcr_test_lft_limitations');
    $r->get('/covid_injections_facts_and_lies/g7_100days_pand_prepare')->to('covid_injections_facts_and_lies#g7_100days_pand_prepare');
    $r->get('/covid_injections_facts_and_lies/kary_mullis_pcr_fauci')->to('covid_injections_facts_and_lies#kary_mullis_pcr_fauci');
    $r->get('/australian_data')->to('australian_data#australian_data');
    $r->get('/australian_data/australian_symptoms')->to('australian_data#australian_symptoms');
    $r->post('/australian_data/australian_symptoms/set_symptom_activity')->to('australian_data#set_symptom_activity');
    $r->get('/miscarriages_within_a_week')->to('miscarriages_within_a_week#miscarriages_within_a_week');
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
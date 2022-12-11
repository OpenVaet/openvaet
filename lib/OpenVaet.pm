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
    $r->get('/studies/verifying_170_cases')->to('verifying_170_cases#verifying_170_cases');
    $r->get('/studies/review_nejm_fda_data')->to('review_nejm_fda_data#review_nejm_fda_data');
    $r->get('/review_nejm_fda_data/study_changelog')->to('review_nejm_fda_data#study_changelog');
    $r->post('/review_nejm_fda_data/load_dose_1_mapping')->to('review_nejm_fda_data#load_dose_1_mapping');
    $r->post('/review_nejm_fda_data/load_dose_1_week_by_week')->to('review_nejm_fda_data#load_dose_1_week_by_week');
    $r->post('/review_nejm_fda_data/load_dose_1_demographic')->to('review_nejm_fda_data#load_dose_1_demographic');
    $r->post('/review_nejm_fda_data/load_dose_2_mapping')->to('review_nejm_fda_data#load_dose_2_mapping');
    $r->post('/review_nejm_fda_data/load_dose_2_week_by_week')->to('review_nejm_fda_data#load_dose_2_week_by_week');
    $r->post('/review_nejm_fda_data/load_dose_2_demographic')->to('review_nejm_fda_data#load_dose_2_demographic');
    $r->post('/review_nejm_fda_data/load_efficacy_cases')->to('review_nejm_fda_data#load_efficacy_cases');
    $r->post('/review_nejm_fda_data/load_efficacy_by_sites')->to('review_nejm_fda_data#load_efficacy_by_sites');
    $r->post('/review_nejm_fda_data/load_efficacy_by_sites_countries')->to('review_nejm_fda_data#load_efficacy_by_sites_countries');
    $r->post('/review_nejm_fda_data/load_efficacy_cases_week_by_week')->to('review_nejm_fda_data#load_efficacy_cases_week_by_week');
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
    $r->get('/studies/pfizer_trial_cases_mapping')->to('pfizer_trial_cases_mapping#pfizer_trial_cases_mapping');
    $r->post('/pfizer_trial_cases_mapping/load_pfizer_trial_cases_mapping')->to('pfizer_trial_cases_mapping#load_pfizer_trial_cases_mapping');
    $r->get('/studies/all_cases_pfizer_trial_cases_mapping')->to('all_cases_pfizer_trial_cases_mapping#all_cases_pfizer_trial_cases_mapping');
    $r->post('/all_cases_pfizer_trial_cases_mapping/load_all_cases_pfizer_trial_cases_mapping')->to('all_cases_pfizer_trial_cases_mapping#load_all_cases_pfizer_trial_cases_mapping');
    $r->get('/studies/all_patients_pfizer_trial_cases_mapping')->to('all_patients_pfizer_trial_cases_mapping#all_patients_pfizer_trial_cases_mapping');
    $r->post('/all_patients_pfizer_trial_cases_mapping/load_all_patients_pfizer_trial_cases_mapping')->to('all_patients_pfizer_trial_cases_mapping#load_all_patients_pfizer_trial_cases_mapping');
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
    $r->get('/covid_injections_facts_and_lies/pcr_test_lft_limitations')->to('covid_injections_facts_and_lies#pcr_test_lft_limitations');
    $r->get('/covid_injections_facts_and_lies/g7_100days_pand_prepare')->to('covid_injections_facts_and_lies#g7_100days_pand_prepare');
    $r->get('/covid_injections_facts_and_lies/kary_mullis_pcr_fauci')->to('covid_injections_facts_and_lies#kary_mullis_pcr_fauci');
    $r->get('/australian_data')->to('australian_data#australian_data');
    $r->get('/australian_data/australian_symptoms')->to('australian_data#australian_symptoms');
    $r->get('/australian_data/australian_vaers_charts')->to('australian_data#australian_vaers_charts');
    $r->get('/usa_moderna_pfizer_deaths_by_groups')->to('usa_moderna_pfizer_deaths_by_groups#usa_moderna_pfizer_deaths_by_groups');
    $r->post('/australian_data/australian_symptoms/set_symptom_activity')->to('australian_data#set_symptom_activity');
    $r->get('/miscarriages_within_a_week')->to('miscarriages_within_a_week#miscarriages_within_a_week');
    $r->get('/census_data')->to('census_data#census_data');
    $r->get('/data_admin')->to('data_admin#data_admin');
    $r->get('/data_admin/symptoms_sets')->to('data_admin#symptoms_sets');
    $r->get('/data_admin/edit_symptoms_set')->to('data_admin#edit_symptoms_set');
    $r->get('/data_admin/new_symptoms_set')->to('data_admin#new_symptoms_set');
    $r->post('/data_admin/save_symptoms_set')->to('data_admin#save_symptoms_set');
    $r->post('/data_admin/save_keywords')->to('data_admin#save_keywords');
    $r->post('/data_admin/set_symptom_activity')->to('data_admin#set_symptom_activity');
    $r->get('/data_admin/keywords_sets')->to('data_admin#keywords_sets');
    $r->get('/data_admin/edit_keywords_set')->to('data_admin#edit_keywords_set');
    $r->get('/data_admin/new_keywords_set')->to('data_admin#new_keywords_set');
    $r->post('/data_admin/save_keywords_set')->to('data_admin#save_keywords_set');
    $r->get('/data_admin/wizards/patient_age')->to('wizard_patient_age#wizard_patient_age');
    $r->post('/wizard_patient_age/load_next_report')->to('wizard_patient_age#load_next_report');
    $r->post('/wizard_patient_age/set_report_attribute')->to('wizard_patient_age#set_report_attribute');
    $r->get('/data_admin/wizards/patient_ages_completed')->to('wizard_patient_age#patient_ages_completed');
    $r->post('/wizard_patient_age/reset_report_attributes')->to('wizard_patient_age#reset_report_attributes');
    $r->get('/data_admin/wizards/patient_ages_custom_export')->to('wizard_patient_age#patient_ages_custom_export');
    $r->post('/wizard_patient_age/generate_products_export')->to('wizard_patient_age#generate_products_export');
    $r->get('/data_admin/wizards/admin_custom_export')->to('wizard_patient_age#admin_custom_export');
    $r->get('/data_admin/wizards/pregnancies_confirmation')->to('wizard_pregnancies_confirmation#wizard_pregnancies_confirmation');
    $r->post('/wizard_pregnancies_confirmation/load_next_report')->to('wizard_pregnancies_confirmation#load_next_report');
    $r->post('/wizard_pregnancies_confirmation/set_report_attribute')->to('wizard_pregnancies_confirmation#set_report_attribute');
    $r->get('/data_admin/wizards/pregnancies_confirmation_completed')->to('wizard_pregnancies_confirmation#pregnancies_confirmation_completed');
    $r->post('/wizard_pregnancies_confirmation/reset_report_attributes')->to('wizard_pregnancies_confirmation#reset_report_attributes');
    $r->get('/data_admin/wizards/breast_milk_exposure_confirmation')->to('wizard_breast_milk_exposure_confirmation#wizard_breast_milk_exposure_confirmation');
    $r->post('/wizard_breast_milk_exposure_confirmation/load_next_report')->to('wizard_breast_milk_exposure_confirmation#load_next_report');
    $r->post('/wizard_breast_milk_exposure_confirmation/set_report_attribute')->to('wizard_breast_milk_exposure_confirmation#set_report_attribute');
    $r->get('/data_admin/wizards/breast_milk_exposure_confirmation_completed')->to('wizard_breast_milk_exposure_confirmation#breast_milk_exposure_confirmation_completed');
    $r->post('/wizard_breast_milk_exposure_confirmation/reset_report_attributes')->to('wizard_breast_milk_exposure_confirmation#reset_report_attributes');
    $r->get('/data_admin/data_completion/by_countries_and_states')->to('data_completion#by_countries_and_states');
    $r->post('/data_completion/load_countries_and_states_data')->to('data_completion#load_countries_and_states_data');
    $r->post('/data_completion/load_wizard_scope')->to('data_completion#load_wizard_scope');
    $r->get('/data_completion/query_stats_refresh')->to('data_completion#query_stats_refresh');
    $r->get('/data_admin/wizards/breast_milk_exposure_post_treatment')->to('wizard_breast_milk_exposure_post_treatment#wizard_breast_milk_exposure_post_treatment');
    $r->post('/wizard_breast_milk_exposure_post_treatment/load_next_report')->to('wizard_breast_milk_exposure_post_treatment#load_next_report');
    $r->post('/wizard_breast_milk_exposure_post_treatment/set_report_attribute')->to('wizard_breast_milk_exposure_post_treatment#set_report_attribute');
    $r->get('/data_admin/wizards/breast_milk_exposure_post_treatment_completed')->to('wizard_breast_milk_exposure_post_treatment#breast_milk_exposure_post_treatment_completed');
    $r->post('/wizard_breast_milk_exposure_post_treatment/reset_report_attributes')->to('wizard_breast_milk_exposure_post_treatment#reset_report_attributes');
    $r->get('/data_admin/wizards/pregnancies_seriousness_confirmation')->to('wizard_pregnancies_seriousness_confirmation#wizard_pregnancies_seriousness_confirmation');
    $r->post('/wizard_pregnancies_seriousness_confirmation/load_next_report')->to('wizard_pregnancies_seriousness_confirmation#load_next_report');
    $r->post('/wizard_pregnancies_seriousness_confirmation/set_report_attribute')->to('wizard_pregnancies_seriousness_confirmation#set_report_attribute');
    $r->get('/data_admin/wizards/pregnancies_seriousness_confirmation_completed')->to('wizard_pregnancies_seriousness_confirmation#pregnancies_seriousness_confirmation_completed');
    $r->post('/wizard_pregnancies_seriousness_confirmation/reset_report_attributes')->to('wizard_pregnancies_seriousness_confirmation#reset_report_attributes');
    $r->get('/social_networks')->to('social_networks#social_networks');
    $r->get('/social_networks/keywords_sets')->to('social_networks#keywords_sets');
    $r->get('/social_networks/edit_keywords_set')->to('social_networks#edit_keywords_set');
    $r->get('/social_networks/new_keywords_set')->to('social_networks#new_keywords_set');
    $r->post('/social_networks/save_keywords_set')->to('social_networks#save_keywords_set');
    $r->post('/social_networks/save_keywords')->to('social_networks#save_keywords');
    $r->get('/social_networks/review_network_posts')->to('social_networks#review_network_posts');
    $r->post('/social_networks/finalize_network_review')->to('social_networks#finalize_network_review');



    $r->get('/tools')->to('tools#tools');
    $r->get('/tools/archive_org_twitter_followers')->to('tools#archive_org_twitter_followers');
    $r->post('/tools/analyze_archive_org_twitter_followers')->to('tools#analyze_archive_org_twitter_followers');
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
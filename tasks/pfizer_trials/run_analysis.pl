#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;

system("perl tasks/pfizer_documents/get_documents.pl");                   # Downloads every archive, extracts them, converts them to PDF.
system("perl tasks/pfizer_trials/subjects_in_sas_files.pl");              # Builds general XPT overview of subjects appearance
system("perl tasks/pfizer_trials/subjects_in_pdf_files_from_sas.pl");     # Builds general PDF overview of subjects appearance
system("perl tasks/pfizer_trials/extract_trial_demographics_1.pl");       # --> 43 451 to Nov 14
system("perl tasks/pfizer_trials/extract_trial_demographics_2.pl");       # --> 43 453 to Nov 14
system("perl tasks/pfizer_trials/compare_pdf_demographics.pl");           # --> 44 267 in the demographic files
system("perl tasks/pfizer_trials/extract_randomization_scheme_1.pl");     # --> 43 551, 43 746 rando, 43 452 d1, 38 964 d2 in randomization file 1
system("perl tasks/pfizer_trials/extract_randomization_scheme_2.pl");     # --> 43 548, 43 743 rando, 43 442 d1, 38 955 d2 in randomization file 2
system("perl tasks/pfizer_trials/compare_pdf_randomizations.pl");         # --> 43 753 in the randomization PDFs merged
system("perl tasks/pfizer_trials/extract_s_d_suppds.pl");
system("perl tasks/pfizer_trials/extract_adva_data.pl");
system("perl tasks/pfizer_trials/analyse_adva_file.pl");                  # --> 43 724 in ADVA, 43 855 total randomized
system("perl tasks/pfizer_trials/eval_screening_from_sas_to_pdf.pl");     # --> 44 404 screenings identified in demographics & sentinels, 103 in discontinued, 66 in interim excluded, 29 in excluded, 20 in measurements, 23 in lab analytic files, 7 in ADVA
system("perl tasks/pfizer_trials/extract_efficacy_cases_1.pl");           # --> 170 efficacy cases.
system("perl tasks/pfizer_trials/extract_all_covid_cases.pl");
system("perl tasks/pfizer_trials/extract_all_covid_cases_april_2021.pl"); # --> 1 168, 351
system("perl tasks/pfizer_trials/compare_covid_cases.pl");                # --> 1 180 total cases.
system("perl tasks/pfizer_trials/merge_doses.pl");
system("perl tasks/pfizer_trials/analyze_efficacy.pl");                   # --> Actual efficacy figures
# die;
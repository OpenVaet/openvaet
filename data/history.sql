############################################################### 
########################### INIT DB ###########################
###############################################################
DROP DATABASE IF EXISTS `openvaet`; # /!\ Comment this line
                                  # once database is 
                                  # initiated. /!\
CREATE DATABASE `openvaet`;
USE `openvaet`;
# data/database/history.sql is the simplest way to boot
# the database to a minimal "functional stage".
######################### END INIT DB #########################

######################### V 1 - 2022-01-11 12:42:00
# Created table ecdc_drug.
CREATE TABLE `openvaet`.`ecdc_drug` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` INT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `url` VARCHAR(500) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_drug_insert` 
BEFORE INSERT ON `ecdc_drug` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_drug_update table.
CREATE TABLE `openvaet`.`ecdc_drug_update` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `drugId` INT NOT NULL,
  `updateTimestamp` INT NOT NULL,
  `total` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_drug_update_insert` 
BEFORE INSERT ON `ecdc_drug_update` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`ecdc_drug_update` 
CHANGE COLUMN `drugId` `ecdcDrugId` INT NOT NULL ,
ADD INDEX `ecdc_drug_update_to_ecdc_drug_idx` (`ecdcDrugId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_drug_update` 
ADD CONSTRAINT `ecdc_drug_update_to_ecdc_drug`
  FOREIGN KEY (`ecdcDrugId`)
  REFERENCES `openvaet`.`ecdc_drug` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Created cdc_state table.
CREATE TABLE `openvaet`.`cdc_state` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` VARCHAR(5) NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_state_insert` 
BEFORE INSERT ON `cdc_state` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_age table.
CREATE TABLE `openvaet`.`cdc_age` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` VARCHAR(5) NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_age_insert` 
BEFORE INSERT ON `cdc_age` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_manufacturer table.
CREATE TABLE `openvaet`.`cdc_manufacturer` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_manufacturer_insert` 
BEFORE INSERT ON `cdc_manufacturer` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_vaccine table.
CREATE TABLE `openvaet`.`cdc_vaccine` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `cdcManufacturerId` INT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `cdc_vaccine_to_cdc_manufacturer_idx` (`cdcManufacturerId` ASC) VISIBLE,
  CONSTRAINT `cdc_vaccine_to_cdc_manufacturer`
    FOREIGN KEY (`cdcManufacturerId`)
    REFERENCES `openvaet`.`cdc_manufacturer` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_vaccine_insert` 
BEFORE INSERT ON `cdc_vaccine` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_report table.
CREATE TABLE `openvaet`.`cdc_report` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` VARCHAR(10) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  `vaccinationTimestamp` INT NULL,
  `reportTimestamp` INT NULL,
  `patientAge` INT NULL,
  `cdcStateId` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_report_insert` 
BEFORE INSERT ON `cdc_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `isSerious` BIT(1) NULL AFTER `patientAge`,
ADD COLUMN `detailsTimestamp` INT NULL AFTER `isSerious`,
CHANGE COLUMN `cdcStateId` `cdcStateId` INT NOT NULL AFTER `id`,
ADD INDEX `cdc_report_to_cdc_state_idx` (`cdcStateId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`cdc_report` 
ADD CONSTRAINT `cdc_report_to_cdc_state`
  FOREIGN KEY (`cdcStateId`)
  REFERENCES `openvaet`.`cdc_state` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Created cdc_state_year table.
CREATE TABLE `openvaet`.`cdc_state_year` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `cdcStateId` INT NOT NULL,
  `year` INT NOT NULL,
  `totalReports` INT NOT NULL,
  `updateTimestamp` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_state_year_insert` 
BEFORE INSERT ON `cdc_state_year` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_sexe table.
CREATE TABLE `openvaet`.`cdc_sexe` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` VARCHAR(5) NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_sexe_insert` 
BEFORE INSERT ON `cdc_sexe` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_country table.
CREATE TABLE `openvaet`.`ecdc_country` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_country_insert` 
BEFORE INSERT ON `ecdc_country` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_age table.
CREATE TABLE `openvaet`.`ecdc_age` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_age_insert` 
BEFORE INSERT ON `ecdc_age` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_country_type table.
CREATE TABLE `openvaet`.`ecdc_country_type` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_country_type_insert` 
BEFORE INSERT ON `ecdc_country_type` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_sexe table.
CREATE TABLE `openvaet`.`ecdc_sexe` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_sexe_insert` 
BEFORE INSERT ON `ecdc_sexe` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_reporter table.
CREATE TABLE `openvaet`.`ecdc_reporter` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_reporter_insert` 
BEFORE INSERT ON `ecdc_reporter` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added stats to ecdc_drug_update.
ALTER TABLE `openvaet`.`ecdc_drug_update` 
ADD COLUMN `stats` JSON NULL AFTER `creationTimestamp`;

# Reworked report data.
ALTER TABLE `openvaet`.`cdc_report` 
DROP COLUMN `isSerious`,
DROP COLUMN `patientAge`,
DROP COLUMN `reportTimestamp`,
DROP COLUMN `vaccinationTimestamp`,
ADD COLUMN `reportData` JSON NULL AFTER `creationTimestamp`;
ALTER TABLE `openvaet`.`ecdc_drug_update` 
ADD UNIQUE INDEX `ecdc_drug_update_unique` (`ecdcDrugId` ASC, `updateTimestamp` ASC) VISIBLE;

# Created source table.
CREATE TABLE `openvaet`.`source` (
  `id` INT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  `indexUpdateTimestamp` INT NULL,
  `fullDrugsUpdateTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_source_insert` 
BEFORE INSERT ON `source` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
INSERT INTO `openvaet`.`source` (`id`, `name`) VALUES ('1', 'ECDC (European Center For Diseases Prevention And Control)');
INSERT INTO `openvaet`.`source` (`id`, `name`) VALUES ('2', 'CDC (Center For Diseases Prevention And Control)');

# Added updateTimestamp to ecdc_drug.
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `updateTimestamp` INT NULL AFTER `creationTimestamp`;

# Added more details to ecdc_drug.
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `ecsApproval` BIT(1) NOT NULL AFTER `url`,
ADD COLUMN `changelog` JSON NOT NULL AFTER `scrappingTimestamp`,
ADD COLUMN `totalCases` INT NOT NULL DEFAULT 0 AFTER `changelog`,
CHANGE COLUMN `updateTimestamp` `scrappingTimestamp` INT NOT NULL ;
ALTER TABLE `openvaet`.`ecdc_drug` 
CHANGE COLUMN `changelog` `changelog` JSON NOT NULL AFTER `creationTimestamp`,
CHANGE COLUMN `scrappingTimestamp` `scrappingTimestamp` INT NULL ;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `updateTimestamp` INT NULL AFTER `scrappingTimestamp`;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `reportsUpdateTimestamp` INT NULL AFTER `updateTimestamp`;

# Created ecdc_year table.
CREATE TABLE `openvaet`.`ecdc_year` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(45) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_year_insert` 
BEFORE INSERT ON `ecdc_year` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_drug_year table.
CREATE TABLE `openvaet`.`ecdc_drug_year` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `ecdcDrugId` INT NOT NULL,
  `ecdcYearId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `ecdc_drug_year_to_ecdc_year_idx` (`ecdcYearId` ASC) VISIBLE,
  CONSTRAINT `ecdc_drug_year_to_ecdc_year`
    FOREIGN KEY (`ecdcYearId`)
    REFERENCES `openvaet`.`ecdc_year` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `ecdc_drug_year_to_ecdc_drug`
    FOREIGN KEY (`ecdcDrugId`)
    REFERENCES `openvaet`.`ecdc_drug` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_drug_year_insert` 
BEFORE INSERT ON `ecdc_drug_year` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_notice table.
CREATE TABLE `openvaet`.`ecdc_notice` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `internalId` VARCHAR(50) NOT NULL,
  `receiptTimestamp` INT NOT NULL,
  `ecdcReportType` INT NOT NULL,
  `ecdcReporterType` INT NOT NULL,
  `ecdcGeographicalOrigin` INT NOT NULL,
  `ICSRUrl` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  `pdfPath` VARCHAR(250) NOT NULL,
  `pdfScrappingTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_notice_insert` 
BEFORE INSERT ON `ecdc_notice` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `ecdcYearId` INT NOT NULL AFTER `receiptTimestamp`,
ADD COLUMN `ecdcSeriousness` INT NOT NULL AFTER `ecdcYearId`;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `textParsingTimestamp` INT NULL AFTER `pdfScrappingTimestamp`;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `formSeriousness` INT NULL AFTER `pdfScrappingTimestamp`,
ADD COLUMN `formSenderType` INT NULL AFTER `formSeriousness`,
ADD COLUMN `formReporterType` INT NULL AFTER `formSenderType`;

# Created ecdc_drug_notice table.
CREATE TABLE `openvaet`.`ecdc_drug_notice` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `ecdcDrugId` INT NOT NULL,
  `ecdcNoticeId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `ecdc_drug_notice_to_ecdc_notice_idx` (`ecdcNoticeId` ASC) VISIBLE,
  CONSTRAINT `ecdc_drug_notice_to_ecdc_drug`
    FOREIGN KEY (`ecdcDrugId`)
    REFERENCES `openvaet`.`ecdc_drug` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `ecdc_drug_notice_to_ecdc_notice`
    FOREIGN KEY (`ecdcNoticeId`)
    REFERENCES `openvaet`.`ecdc_notice` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_drug_notice_insert` 
BEFORE INSERT ON `ecdc_drug_notice` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_reaction table.
CREATE TABLE `openvaet`.`ecdc_reaction` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_reaction_insert` 
BEFORE INSERT ON `ecdc_reaction` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_reaction_outcome table.
CREATE TABLE `openvaet`.`ecdc_reaction_outcome` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_reaction_outcome_insert` 
BEFORE INSERT ON `ecdc_reaction_outcome` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_reaction_seriousness table.
CREATE TABLE `openvaet`.`ecdc_reaction_seriousness` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_reaction_seriousness_insert` 
BEFORE INSERT ON `ecdc_reaction_seriousness` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created ecdc_notice_reaction table.
CREATE TABLE `openvaet`.`ecdc_notice_reaction` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `ecdcNoticeId` INT NOT NULL,
  `ecdcReactionId` INT NOT NULL,
  `ecdcReactionSeriousnessId` INT NOT NULL,
  `ecdcReactionOutcomeId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_notice_reaction_insert` 
BEFORE INSERT ON `ecdc_notice_reaction` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`ecdc_notice_reaction` 
ADD INDEX `ecdc_notice_reaction_to_ecdc_notice_idx` (`ecdcNoticeId` ASC) VISIBLE,
ADD INDEX `ecdc_notice_reaction_to_ecdc_reaction_idx` (`ecdcReactionId` ASC) VISIBLE,
ADD INDEX `ecdc_notice_reaction_to_ecdc_reaction_seriousness_idx` (`ecdcReactionSeriousnessId` ASC) VISIBLE,
ADD INDEX `ecdc_notice_reaction_to_ecdc_reaction_outcome_idx` (`ecdcReactionOutcomeId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_notice_reaction` 
ADD CONSTRAINT `ecdc_notice_reaction_to_ecdc_notice`
  FOREIGN KEY (`ecdcNoticeId`)
  REFERENCES `openvaet`.`ecdc_notice` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION,
ADD CONSTRAINT `ecdc_notice_reaction_to_ecdc_reaction`
  FOREIGN KEY (`ecdcReactionId`)
  REFERENCES `openvaet`.`ecdc_reaction` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION,
ADD CONSTRAINT `ecdc_notice_reaction_to_ecdc_reaction_seriousness`
  FOREIGN KEY (`ecdcReactionSeriousnessId`)
  REFERENCES `openvaet`.`ecdc_reaction_seriousness` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION,
ADD CONSTRAINT `ecdc_notice_reaction_to_ecdc_reaction_outcome`
  FOREIGN KEY (`ecdcReactionOutcomeId`)
  REFERENCES `openvaet`.`ecdc_reaction_outcome` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Added faultyNoticeDetailsParsing & ecdcAgeGroup to ecdc_notice.
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `faultyNoticeDetailsParsing` BIT(1) NOT NULL DEFAULT 0 AFTER `textParsingTimestamp`;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `ecdcAgeGroup` INT NULL AFTER `faultyNoticeDetailsParsing`;
ALTER TABLE `openvaet`.`ecdc_notice` 
CHANGE COLUMN `ecdcAgeGroup` `ecdcAgeGroup` INT NOT NULL ;
ALTER TABLE `openvaet`.`ecdc_notice` 
CHANGE COLUMN `ecdcAgeGroup` `ecdcAgeGroup` INT NOT NULL ;

# Added aeFromEcdcYearId & hasNullGateYear to ecdc_drug.
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `aeFromEcdcYearId` INT NULL AFTER `totalCases`,
ADD INDEX `ecdc_drug_to_ecdc_year_idx` (`aeFromEcdcYearId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD CONSTRAINT `ecdc_drug_to_ecdc_year`
  FOREIGN KEY (`aeFromEcdcYearId`)
  REFERENCES `openvaet`.`ecdc_year` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `hasNullGateYear` BIT(1) NOT NULL DEFAULT 0 AFTER `aeFromEcdcYearId`;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `earliestListedEcdcYearId` INT NULL AFTER `hasNullGateYear`,
CHANGE COLUMN `hasNullGateYear` `hasNullGateYear` BIT(1) NOT NULL DEFAULT b'0' AFTER `updateTimestamp`,
CHANGE COLUMN `aeFromEcdcYearId` `aeFromEcdcYearId` INT NULL DEFAULT NULL AFTER `earliestListedEcdcYearId`,
CHANGE COLUMN `totalCases` `totalCases` INT NOT NULL DEFAULT '0' AFTER `aeFromEcdcYearId`,
ADD INDEX `ecdc_drug_to_earliest_ecdc_year_idx` (`earliestListedEcdcYearId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD CONSTRAINT `ecdc_drug_to_earliest_ecdc_year`
  FOREIGN KEY (`earliestListedEcdcYearId`)
  REFERENCES `openvaet`.`ecdc_year` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD UNIQUE INDEX `ecdc_notice_internalId_unique` (`internalId` ASC) VISIBLE;

# Created ecdc_drug_year_seriousness table.
CREATE TABLE `ecdc_drug_year_seriousness` (
  `id` int NOT NULL AUTO_INCREMENT,
  `ecdcDrugId` int NOT NULL,
  `ecdcYearId` int NOT NULL,
  `ecdcSeriousness` int NOT NULL,
  `totalCases` int NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ecdc_drug_year_seriousness_to_ecdc_year_idx` (`ecdcYearId`),
  KEY `ecdc_drug_year_seriousness_to_ecdc_drug` (`ecdcDrugId`),
  CONSTRAINT `ecdc_drug_year_seriousness_to_ecdc_drug` FOREIGN KEY (`ecdcDrugId`) REFERENCES `ecdc_drug` (`id`),
  CONSTRAINT `ecdc_drug_year_seriousness_to_ecdc_year` FOREIGN KEY (`ecdcYearId`) REFERENCES `ecdc_year` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_drug_year_seriousness_insert` 
BEFORE INSERT ON `ecdc_drug_year_seriousness` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`ecdc_drug_year_seriousness` 
ADD COLUMN `updateTimestamp` INT NOT NULL AFTER `creationTimestamp`;

# Renamed typo in ecdc_sexe to ecdc_sex.
ALTER TABLE `openvaet`.`ecdc_sexe` 
RENAME TO  `openvaet`.`ecdc_sex` ;

# Removed obsolete earliestListedEcdcYearId from ecdc_drug ; added overviewStats, earliestAERTimestamp, totalCasesScrapped & ecdcSexId ; changed totalCases to totalCasesDisplayed.
ALTER TABLE `openvaet`.`ecdc_drug` 
DROP FOREIGN KEY `ecdc_drug_to_earliest_ecdc_year`;
ALTER TABLE `openvaet`.`ecdc_drug` 
DROP COLUMN `earliestListedEcdcYearId`,
DROP INDEX `ecdc_drug_to_earliest_ecdc_year_idx` ;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `overviewStats` JSON NULL AFTER `changelog`;
ALTER TABLE `openvaet`.`ecdc_drug` 
CHANGE COLUMN `updateTimestamp` `updateTimestamp` INT NULL DEFAULT NULL AFTER `overviewStats`;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `ecdcSexId` INT NOT NULL AFTER `ecdcAgeGroup`,
ADD INDEX `ecdc_notice_to_ecdc_sex_idx` (`ecdcSexId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD CONSTRAINT `ecdc_notice_to_ecdc_sex`
  FOREIGN KEY (`ecdcSexId`)
  REFERENCES `openvaet`.`ecdc_sex` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `earliestAERTimestamp` INT NULL AFTER `totalCases`;
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `totalCasesScrapped` INT NOT NULL AFTER `totalCasesDisplayed`,
CHANGE COLUMN `totalCases` `totalCasesDisplayed` INT NOT NULL DEFAULT '0' ;

# Created ecdc_reporter_organisation table.
CREATE TABLE `openvaet`.`ecdc_reporter_organisation` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_ecdc_reporter_organisation_insert` 
BEFORE INSERT ON `ecdc_reporter_organisation` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added ecdcReporterOrganisationId to ecdc_notice.
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `ecdcReporterOrganisationId` INT NULL AFTER `formReporterType`,
ADD INDEX `ecdc_notice_to_ecdc_reporter_organisation_idx` (`ecdcReporterOrganisationId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD CONSTRAINT `ecdc_notice_to_ecdc_reporter_organisation`
  FOREIGN KEY (`ecdcReporterOrganisationId`)
  REFERENCES `openvaet`.`ecdc_reporter_organisation` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Added default value to totalCasesScrapped.
ALTER TABLE `openvaet`.`ecdc_drug` 
CHANGE COLUMN `totalCasesScrapped` `totalCasesScrapped` INT NOT NULL DEFAULT 0 ;

# Added isIndexed to ecdc_drug.
ALTER TABLE `openvaet`.`ecdc_drug` 
ADD COLUMN `isIndexed` BIT(1) NOT NULL DEFAULT 0 AFTER `earliestAERTimestamp`,
ADD COLUMN `indexationTimestamp` INT NULL AFTER `isIndexed`;

# Created cdc_vaccine_type table.
CREATE TABLE `cdc_vaccine_type` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_vaccine_type_insert` 
BEFORE INSERT ON `cdc_vaccine_type` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added cdcVaccineTypeId to cdc_vaccine table.
ALTER TABLE `openvaet`.`cdc_vaccine` 
ADD COLUMN `cdcVaccineTypeId` INT NOT NULL AFTER `id`,
ADD INDEX `cdc_vaccine_to_cdc_vaccine_type_idx` (`cdcVaccineTypeId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`cdc_vaccine` 
ADD CONSTRAINT `cdc_vaccine_to_cdc_vaccine_type`
  FOREIGN KEY (`cdcVaccineTypeId`)
  REFERENCES `openvaet`.`cdc_vaccine_type` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Created cdc_symptom table.
CREATE TABLE `cdc_symptom` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_symptom_insert` 
BEFORE INSERT ON `cdc_symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_report_symptom table.
CREATE TABLE `openvaet`.`cdc_report_symptom` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `cdcReportId` INT NOT NULL,
  `cdcSymptomId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `cdc_report_symptom_to_cdc_symptom_idx` (`cdcSymptomId` ASC) VISIBLE,
  CONSTRAINT `cdc_report_symptom_to_cdc_report`
    FOREIGN KEY (`cdcReportId`)
    REFERENCES `openvaet`.`cdc_report` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `cdc_report_symptom_to_cdc_symptom`
    FOREIGN KEY (`cdcSymptomId`)
    REFERENCES `openvaet`.`cdc_symptom` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_report_symptom_insert` 
BEFORE INSERT ON `cdc_report_symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created cdc_report_vaccine table.
CREATE TABLE `openvaet`.`cdc_report_vaccine` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `cdcReportId` INT NOT NULL,
  `cdcVaccineId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `cdc_report_vaccine_to_cdc_vaccine_idx` (`cdcVaccineId` ASC) VISIBLE,
  CONSTRAINT `cdc_report_vaccine_to_cdc_report`
    FOREIGN KEY (`cdcReportId`)
    REFERENCES `openvaet`.`cdc_report` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `cdc_report_vaccine_to_cdc_vaccine`
    FOREIGN KEY (`cdcVaccineId`)
    REFERENCES `openvaet`.`cdc_vaccine` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_report_vaccine_insert` 
BEFORE INSERT ON `cdc_report_vaccine` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`cdc_report_vaccine` 
ADD COLUMN `dose` VARCHAR(3) NOT NULL AFTER `creationTimestamp`;

# Added parsing details to cdc_report.
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `vaccinationDate` VARCHAR(10) NULL AFTER `detailsTimestamp`,
ADD COLUMN `cdcReceptionDate` VARCHAR(10) NULL AFTER `vaccinationDate`,
ADD COLUMN `cdcSex` INT NULL AFTER `cdcReceptionDate`,
ADD COLUMN `cdcSeriousness` INT NULL AFTER `cdcSex`,
ADD COLUMN `cdcVaccineAdministrator` INT NULL AFTER `cdcSeriousness`,
ADD COLUMN `patientAge` DOUBLE NULL AFTER `cdcVaccineAdministrator`,
ADD COLUMN `aEDescription` LONGTEXT NULL AFTER `patientAge`,
ADD COLUMN `patientDied` BIT(1) NOT NULL DEFAULT 0 AFTER `aEDescription`,
ADD COLUMN `lifeThreatning` BIT(1) NOT NULL DEFAULT 0 AFTER `patientDied`,
ADD COLUMN `hospitalized` BIT(1) NOT NULL DEFAULT 0 AFTER `lifeThreatning`,
ADD COLUMN `permanentDisability` BIT(1) NOT NULL DEFAULT 0 AFTER `hospitalized`,
ADD COLUMN `parsingTimestamp` INT NULL AFTER `permanentDisability`;

# Optimized DB parsing with additional indexes.
ALTER TABLE `openvaet`.`cdc_report` 
ADD INDEX `cdc_report_cdcSex` (`cdcSex` ASC) VISIBLE;

# Added extrapolation data to ecdc_notice to optimize indexing.
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `hasDied` BIT(1) NOT NULL DEFAULT 0 AFTER `ecdcSexId`,
ADD COLUMN `isSerious` BIT(1) NOT NULL DEFAULT 0 AFTER `hasDied`;

# Restored missing relation to sex in cdc_report.
ALTER TABLE `openvaet`.`cdc_report` 
CHANGE COLUMN `cdcSex` `cdcSexId` INT NULL DEFAULT NULL ;
ALTER TABLE `openvaet`.`cdc_report` 
ADD CONSTRAINT `cdc_report_to_cdc_sexe`
  FOREIGN KEY (`cdcSexId`)
  REFERENCES `openvaet`.`cdc_sexe` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`cdc_report` 
DROP FOREIGN KEY `cdc_report_to_cdc_sexe`;
ALTER TABLE `openvaet`.`cdc_report` 
CHANGE COLUMN `cdcSexId` `cdcSexeId` INT NULL DEFAULT NULL ;
ALTER TABLE `openvaet`.`cdc_report` 
ADD CONSTRAINT `cdc_report_to_cdc_sexe`
  FOREIGN KEY (`cdcSexeId`)
  REFERENCES `openvaet`.`cdc_sexe` (`id`);
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `deceasedDate` VARCHAR(10) NULL AFTER `cdcReceptionDate`;
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `cdcAgeId` INT NULL AFTER `cdcStateId`,
ADD INDEX `cdc_report_to_cdc_age_idx` (`cdcAgeId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`cdc_report` 
ADD CONSTRAINT `cdc_report_to_cdc_age`
  FOREIGN KEY (`cdcAgeId`)
  REFERENCES `openvaet`.`cdc_age` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Removed obsolete cdc_report & ecdc_notice details.
ALTER TABLE `openvaet`.`cdc_report` 
DROP COLUMN `detailsTimestamp`,
DROP COLUMN `reportData`;

# Added totalReports to source.
ALTER TABLE `openvaet`.`source` 
ADD COLUMN `totalReports` INT NOT NULL DEFAULT 0 AFTER `fullDrugsUpdateTimestamp`;

# Created email table (people who wish to be informed of further updates).
CREATE TABLE `openvaet`.`email` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `email` VARCHAR(500) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_email_insert` 
BEFORE INSERT ON `email` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created session table.
CREATE TABLE `openvaet`.`session` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `ipAddress` VARCHAR(25) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `session_unique_ip` (`ipAddress` ASC) VISIBLE);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_session_insert` 
BEFORE INSERT ON `session` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`email` 
ADD COLUMN `sessionId` INT NOT NULL AFTER `id`,
ADD INDEX `email_to_session_idx` (`sessionId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`email` 
ADD CONSTRAINT `email_to_session`
  FOREIGN KEY (`sessionId`)
  REFERENCES `openvaet`.`session` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`email` 
ADD UNIQUE INDEX `email_unique` (`sessionId` ASC, `email` ASC) VISIBLE;

# Created contact table.
CREATE TABLE `contact` (
  `id` int NOT NULL AUTO_INCREMENT,
  `sessionId` int NOT NULL,
  `email` varchar(500) NOT NULL,
  `text` LONGTEXT NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`),
  KEY `contact_to_session_idx` (`sessionId`),
  CONSTRAINT `contact_to_session` FOREIGN KEY (`sessionId`) REFERENCES `session` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_contact_insert` 
BEFORE INSERT ON `contact` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

######################### V 2 - 2022-05-08 08:30:00
# Initiated a temporary set of tables to work on the fertility study ; prior merging it with the rest of the infrastructure.
# Created vaers_fertility_symptom table.
CREATE TABLE `openvaet`.`vaers_fertility_symptom` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  `discarded` BIT(1) NOT NULL,
  `discardTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_vaers_fertility_symptom_insert` 
BEFORE INSERT ON `vaers_fertility_symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`vaers_fertility_symptom` 
CHANGE COLUMN `discarded` `discarded` BIT(1) NOT NULL DEFAULT 0 ;
ALTER TABLE `openvaet`.`vaers_fertility_symptom` 
ADD COLUMN `pregnancyRelated` BIT(1) NOT NULL DEFAULT 0 AFTER `discardTimestamp`,
ADD COLUMN `pregnancyRelatedTimestamp` INT NULL AFTER `pregnancyRelated`;
ALTER TABLE `openvaet`.`vaers_fertility_symptom` 
ADD COLUMN `severePregnancyRelated` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyRelatedTimestamp`,
ADD COLUMN `severePregnancyRelatedTimestamp` INT NULL AFTER `severePregnancyRelated`;
ALTER TABLE `openvaet`.`vaers_fertility_symptom` 
ADD COLUMN `menstrualDisorderRelated` BIT(1) NOT NULL DEFAULT 0 AFTER `severePregnancyRelatedTimestamp`,
ADD COLUMN `menstrualDisorderRelatedTimestamp` INT NULL AFTER `menstrualDisorderRelated`;

# Created vaers_fertility_report table.
CREATE TABLE `openvaet`.`vaers_fertility_report` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `vaersId` INT NOT NULL,
  `aEDescription` LONGTEXT NOT NULL,
  `vaersVaccine` INT NOT NULL,
  `vaersSex` INT NOT NULL,
  `patientAge` DOUBLE NULL,
  `creationTimestamp` INT NOT NULL,
  `pregnancyConfirmation` BIT(1) NULL,
  `pregnancyConfirmationTimestamp` INT NULL,
  `femaleFromPregnancyConfirmation` BIT(1) NULL,
  `femaleFromPregnancyConfirmationTimestamp` INT NULL,
  `patientAgeConfirmation` INT NULL,
  `patientAgeConfirmationTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_vaers_fertility_report_insert` 
BEFORE INSERT ON `vaers_fertility_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `pregnancyConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyConfirmationTimestamp`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `vaccinationDate` VARCHAR(45) NULL AFTER `vaersSex`,
ADD COLUMN `reportDate` VARCHAR(45) NOT NULL AFTER `vaccinationDate`,
ADD COLUMN `patientAgeCorrected` DOUBLE NULL AFTER `patientAge`,
ADD COLUMN `vaersSexCorrected` INT NULL AFTER `patientAgeCorrected`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
CHANGE COLUMN `reportDate` `vaersReceptionDate` VARCHAR(45) NOT NULL ;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD UNIQUE INDEX `vaers_fertility_report_unique` (`vaersId` ASC);
ALTER TABLE `openvaet`.`vaers_fertility_report` 
CHANGE COLUMN `vaersId` `vaersId` VARCHAR(45) NOT NULL ;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `symptomsListed` JSON NOT NULL AFTER `vaersSexCorrected`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `hospitalized` BIT(1) NOT NULL AFTER `patientAgeConfirmationTimestamp`,
ADD COLUMN `permanentDisability` BIT(1) NOT NULL AFTER `hospitalized`,
ADD COLUMN `lifeThreatning` BIT(1) NOT NULL AFTER `permanentDisability`,
ADD COLUMN `patientDied` BIT(1) NOT NULL AFTER `lifeThreatning`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `menstrualCycleDisordersConfirmation` BIT(1) NULL AFTER `patientAgeConfirmationTimestamp`,
ADD COLUMN `menstrualCycleDisordersConfirmationTimestamp` INT NULL AFTER `menstrualCycleDisordersConfirmation`,
ADD COLUMN `menstrualCycleDisordersConfirmationRequired` BIT(1) NULL AFTER `menstrualCycleDisordersConfirmationTimestamp`,
CHANGE COLUMN `hospitalized` `hospitalized` BIT(1) NOT NULL AFTER `symptomsListed`,
CHANGE COLUMN `permanentDisability` `permanentDisability` BIT(1) NOT NULL AFTER `hospitalized`,
CHANGE COLUMN `lifeThreatning` `lifeThreatning` BIT(1) NOT NULL AFTER `permanentDisability`,
CHANGE COLUMN `patientDied` `patientDied` BIT(1) NOT NULL AFTER `lifeThreatning`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `babyExposureConfirmation` BIT(1) NULL AFTER `menstrualCycleDisordersConfirmationRequired`,
ADD COLUMN `babyExposureConfirmationTimestamp` INT NULL AFTER `babyExposureConfirmation`,
ADD COLUMN `babyExposureConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `babyExposureConfirmationTimestamp`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `seriousnessConfirmation` BIT(1) NULL AFTER `menstrualCycleDisordersConfirmationRequired`,
ADD COLUMN `seriousnessConfirmationTimestamp` INT NULL AFTER `seriousnessConfirmation`,
ADD COLUMN `seriousnessConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `seriousnessConfirmationTimestamp`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `patientDiedFixed` BIT(1) NULL AFTER `babyExposureConfirmationRequired`,
ADD COLUMN `lifeThreatningFixed` BIT(1) NULL AFTER `patientDiedFixed`,
ADD COLUMN `permanentDisabilityFixed` BIT(1) NULL AFTER `lifeThreatningFixed`,
ADD COLUMN `hospitalizedFixed` BIT(1) NULL AFTER `permanentDisabilityFixed`;
UPDATE vaers_fertility_report SET patientDiedFixed = patientDied, lifeThreatningFixed = lifeThreatning, permanentDisabilityFixed = permanentDisability, hospitalizedFixed = hospitalized WHERE id > 0;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
CHANGE COLUMN `patientDiedFixed` `patientDiedFixed` BIT(1) NOT NULL ,
CHANGE COLUMN `lifeThreatningFixed` `lifeThreatningFixed` BIT(1) NOT NULL ,
CHANGE COLUMN `permanentDisabilityFixed` `permanentDisabilityFixed` BIT(1) NOT NULL ,
CHANGE COLUMN `hospitalizedFixed` `hospitalizedFixed` BIT(1) NOT NULL ;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `childDied` BIT(1) NOT NULL DEFAULT 0 AFTER `hospitalizedFixed`,
ADD COLUMN `childLifeThreatned` BIT(1) NOT NULL DEFAULT 0 AFTER `childDied`,
ADD COLUMN `childSeriousAE` BIT(1) NOT NULL DEFAULT 0 AFTER `childLifeThreatned`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
DROP COLUMN `childLifeThreatned`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `hoursBetweenVaccineAndAE` DOUBLE NULL AFTER `childSeriousAE`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `onsetDate` VARCHAR(45) NULL AFTER `vaersSex`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `vaccinationDateFixed` VARCHAR(45) NULL AFTER `babyExposureConfirmationRequired`,
ADD COLUMN `onsetDateFixed` VARCHAR(45) NULL AFTER `vaccinationDateFixed`;
ALTER TABLE `openvaet`.`vaers_fertility_symptom` 
ADD COLUMN `foetalDeathRelated` BIT(1) NOT NULL DEFAULT 0 AFTER `menstrualDisorderRelatedTimestamp`,
ADD COLUMN `foetalDeathRelatedTimestamp` INT NULL AFTER `foetalDeathRelated`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `pregnancyDetailsConfirmation` BIT(1) NULL AFTER `hoursBetweenVaccineAndAE`,
ADD COLUMN `pregnancyDetailsConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyDetailsConfirmation`,
ADD COLUMN `pregnancyDetailsConfirmationTimestamp` INT NULL AFTER `pregnancyDetailsConfirmationRequired`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `accurateDates` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyDetailsConfirmationTimestamp`,
ADD COLUMN `motherAgeFixed` DOUBLE NULL AFTER `accurateDates`,
ADD COLUMN `patientAgeFixed` DOUBLE NULL AFTER `motherAgeFixed`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
CHANGE COLUMN `patientAgeFixed` `childAgeFixed` DOUBLE NULL DEFAULT NULL ;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
DROP COLUMN `patientAgeCorrected`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `miscarriageOnWeek` DOUBLE NULL AFTER `childAgeWeekFixed`,
CHANGE COLUMN `childAgeFixed` `childAgeWeekFixed` DOUBLE NULL DEFAULT NULL ;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `lmpDate` VARCHAR(45) NULL AFTER `miscarriageOnWeek`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
DROP COLUMN `accurateDates`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `hasLikelyPregnancySymptom` BIT(1) NOT NULL DEFAULT 0 AFTER `creationTimestamp`,
ADD COLUMN `hasDirectPregnancySymptom` BIT(1) NOT NULL DEFAULT 0 AFTER `hasLikelyPregnancySymptom`;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD COLUMN `cdcStateId` INT NULL AFTER `vaersSex`,
ADD INDEX `vaers_fertility_report_to_cdc_state_idx` (`cdcStateId` ASC) VISIBLE;
ALTER TABLE `openvaet`.`vaers_fertility_report` 
ADD CONSTRAINT `vaers_fertility_report_to_cdc_state`
  FOREIGN KEY (`cdcStateId`)
  REFERENCES `openvaet`.`cdc_state` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

######################### V 3 - 2022-06-20 11:50:00
# Added detailsTimestamp & immProjectNumber to cdc_report.
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `detailsTimestamp` INT NULL AFTER `parsingTimestamp`;
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `immProjectNumber` VARCHAR(10) NULL AFTER `internalId`;
ALTER TABLE `openvaet`.`cdc_report` 
CHANGE COLUMN `immProjectNumber` `immProjectNumber` VARCHAR(50) NULL DEFAULT NULL ;

# Added internal id to cdc_manufacturer.
ALTER TABLE `openvaet`.`cdc_manufacturer` 
ADD COLUMN `internalId` VARCHAR(45) NOT NULL AFTER `id`;

# Created cdc_dose table.
CREATE TABLE `openvaet`.`cdc_dose` (
  `id` int NOT NULL AUTO_INCREMENT,
  `internalId` varchar(45) NOT NULL,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_cdc_dose_insert` 
BEFORE INSERT ON `cdc_dose` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

######################### V 4 - 2022-07-17 04:35:00
# Created twitter_user table.
CREATE TABLE `openvaet`.`twitter_user` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `twitterId` BIGINT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `profileImageUrl` VARCHAR(500) NOT NULL,
  `followersCount` INT NOT NULL,
  `followingCount` INT NOT NULL,
  `tweetCount` INT NOT NULL,
  `twitterUserName` VARCHAR(250) NOT NULL,
  `createdOn` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE INDEX `twitter_user_unique_id` (`twitterId` ASC) INVISIBLE,
  UNIQUE INDEX `twitter_user_unique_name` (`name` ASC) VISIBLE);
ALTER TABLE `openvaet`.`twitter_user` 
CHANGE COLUMN `tweetCount` `tweetsCount` INT NOT NULL ;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_twitter_user_insert` 
BEFORE INSERT ON `twitter_user` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`twitter_user` 
ADD COLUMN `description` LONGTEXT NULL AFTER `creationTimestamp`;
ALTER TABLE `openvaet`.`twitter_user` 
ADD COLUMN `websiteUrl` VARCHAR(500) NULL AFTER `description`;
ALTER TABLE `openvaet`.`twitter_user` 
DROP COLUMN `description`,
CHANGE COLUMN `twitterUserName` `twitterUserName` VARCHAR(250) NOT NULL AFTER `md5`,
CHANGE COLUMN `name` `md5` VARCHAR(250) NOT NULL ;
ALTER TABLE `openvaet`.`twitter_user` 
ADD COLUMN `updateTimestamp` INT NULL AFTER `websiteUrl`;

# Created twitter_user_relation table.
CREATE TABLE `openvaet`.`twitter_user_relation` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `twitterUserRelationType` INT NOT NULL,
  `twitterUser1Id` INT NOT NULL,
  `twitterUser2Id` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
ALTER TABLE `openvaet`.`twitter_user_relation` 
CHANGE COLUMN `twitterUserRelationType` `twitterUserRelationType` INT NOT NULL AFTER `twitterUser2Id`;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_twitter_user_relation_insert` 
BEFORE INSERT ON `twitter_user_relation` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created twitter_user_relation_page table.
CREATE TABLE `openvaet`.`twitter_user_relation_page` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `twitterUserId` INT NOT NULL,
  `token` VARCHAR(50) NULL,
  `creationTimestamp` INT NOT NULL,
  `updateTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_twitter_user_relation_page_insert` 
BEFORE INSERT ON `twitter_user_relation_page` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`twitter_user_relation_page` 
CHANGE COLUMN `token` `nextToken` VARCHAR(50) NULL DEFAULT NULL ;
DROP TABLE `openvaet`.`twitter_user_relation_page`;
DROP TABLE `openvaet`.`twitter_user_relation`;
DROP TABLE `openvaet`.`twitter_user`;

######################### V 5 - 2022-08-21 01:45:00
# Created aus_symptom table.
CREATE TABLE `openvaet`.`aus_symptom` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(250) NOT NULL,
  `timeSeen` INT NOT NULL,
  `active` BIT(1) NOT NULL DEFAULT 0,
  `creationTimestamp` INT NOT NULL,
  `activeTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_aus_symptom_insert` 
BEFORE INSERT ON `aus_symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created user table.
CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(250) NOT NULL,
  `emailVerification` bit(1) NOT NULL DEFAULT b'0',
  `emailVerificationCode` varchar(6) NOT NULL,
  `password` varchar(100) NOT NULL,
  `emailVerificationTimestamp` int DEFAULT NULL,
  `failedAccessCount` int NOT NULL DEFAULT '0',
  `token` varchar(100) DEFAULT NULL,
  `lockoutUntilDatetime` datetime DEFAULT NULL,
  `lastLoginTimestamp` int DEFAULT NULL,
  `creationTimestamp` int NOT NULL,
  `isAdmin` bit(1) NOT NULL DEFAULT b'0',
  `phoneNumber` varchar(20) DEFAULT NULL,
  `passwordReinitCode` varchar(6) DEFAULT NULL,
  `passwordReinitAttempts` int NOT NULL DEFAULT '0',
  `passwordReinitTimestamp` int DEFAULT NULL,
  `passwordReinitFailedAttemtps` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_unique` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_user_insert` 
BEFORE INSERT ON `user` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created user_twitter_ban table.
CREATE TABLE `openvaet`.`user_twitter_ban` (
  `id` INT NOT NULL,
  `twitterUserName` VARCHAR(45) NOT NULL,
  `userId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  INDEX `user_twitter_ban_to_user_idx` (`userId` ASC),
  CONSTRAINT `user_twitter_ban_to_user`
    FOREIGN KEY (`userId`)
    REFERENCES `openvaet`.`user` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_user_twitter_ban_insert` 
BEFORE INSERT ON `user_twitter_ban` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`user_twitter_ban` 
CHANGE COLUMN `userId` `userId` INT(11) NOT NULL AFTER `id`,
CHANGE COLUMN `twitterUserName` `twitterUserName` VARCHAR(250) NOT NULL ;
ALTER TABLE `openvaet`.`user_twitter_ban` 
CHANGE COLUMN `id` `id` INT NOT NULL AUTO_INCREMENT ;
ALTER TABLE `openvaet`.`user_twitter_ban` 
ADD COLUMN `networkName` VARCHAR(250) NOT NULL AFTER `twitterUserName`;

######################### V 6 - 2022-08-27 20:10:00
# Added hasClosedDisclaimer to user.
ALTER TABLE `openvaet`.`user` 
ADD COLUMN `hasClosedDisclaimer` BIT(1) NOT NULL DEFAULT 0 AFTER `passwordReinitFailedAttemtps`;

# Added isPublished tag to ecdc_notice & cdc_report.
ALTER TABLE `openvaet`.`ecdc_notice` 
ADD COLUMN `isPublished` BIT(1) NOT NULL DEFAULT 1 AFTER `isSerious`;
ALTER TABLE `openvaet`.`cdc_report` 
ADD COLUMN `isPublished` BIT(1) NOT NULL DEFAULT 1 AFTER `parsingTimestamp`;

######################### V 7 - 2022-09-01 20:10:00
# Created vaers_deaths_symptom table.
CREATE TABLE `vaers_deaths_symptom` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  `discarded` bit(1) NOT NULL DEFAULT b'0',
  `discardTimestamp` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_vaers_deaths_symptom_insert` 
BEFORE INSERT ON `vaers_deaths_symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created vaers_deaths_report table.
CREATE TABLE `vaers_deaths_report` (
  `id` int NOT NULL AUTO_INCREMENT,
  `vaersId` varchar(45) NOT NULL,
  `aEDescription` longtext NOT NULL,
  `vaersVaccine` int NOT NULL,
  `vaersSex` int NOT NULL,
  `vaersSexCorrected` int DEFAULT NULL,
  `cdcStateId` int DEFAULT NULL,
  `onsetDate` varchar(45) DEFAULT NULL,
  `onsetDateFixed` varchar(45) DEFAULT NULL,
  `vaccinationDate` varchar(45) DEFAULT NULL,
  `vaccinationDateFixed` varchar(45) DEFAULT NULL,
  `vaersReceptionDate` varchar(45) NOT NULL,
  `patientAge` double DEFAULT NULL,
  `patientAgeFixed` double DEFAULT NULL,
  `symptomsListed` json NOT NULL,
  `hospitalized` bit(1) NOT NULL,
  `hospitalizedFixed` bit(1) NOT NULL,
  `permanentDisability` bit(1) NOT NULL,
  `permanentDisabilityFixed` bit(1) NOT NULL,
  `lifeThreatning` bit(1) NOT NULL,
  `lifeThreatningFixed` bit(1) NOT NULL,
  `patientDied` bit(1) NOT NULL,
  `patientDiedFixed` bit(1) NOT NULL,
  `creationTimestamp` int NOT NULL,
  `patientAgeConfirmation` int DEFAULT NULL,
  `patientAgeConfirmationTimestamp` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `vaers_deaths_report_unique` (`vaersId`),
  KEY `vaers_deaths_report_to_cdc_state_idx` (`cdcStateId`),
  CONSTRAINT `vaers_deaths_report_to_cdc_state` FOREIGN KEY (`cdcStateId`) REFERENCES `cdc_state` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_vaers_deaths_report_insert` 
BEFORE INSERT ON `vaers_deaths_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`vaers_deaths_report` 
CHANGE COLUMN `vaersVaccine` `vaccinesListed` JSON NOT NULL ;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
ADD COLUMN `deceasedDate` VARCHAR(45) NULL AFTER `onsetDateFixed`,
ADD COLUMN `deceasedDateFixed` VARCHAR(45) NULL AFTER `deceasedDate`,
CHANGE COLUMN `vaersSexCorrected` `vaersSexFixed` INT NULL DEFAULT NULL ;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
ADD COLUMN `changelog` JSON NULL AFTER `patientAgeConfirmationTimestamp`;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
DROP COLUMN `changelog`,
ADD COLUMN `userId` INT NOT NULL AFTER `patientAgeConfirmationTimestamp`,
ADD INDEX `vaers_deaths_report_to_user_idx` (`userId` ASC);
ALTER TABLE `openvaet`.`vaers_deaths_report` 
CHANGE COLUMN `userId` `userId` INT NULL ;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
ADD CONSTRAINT `vaers_deaths_report_to_user`
  FOREIGN KEY (`userId`)
  REFERENCES `openvaet`.`user` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
ADD COLUMN `patientAgeConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `userId`;
ALTER TABLE `openvaet`.`vaers_deaths_report` 
ADD COLUMN `hoursBetweenVaccineAndAE` DOUBLE NULL AFTER `patientAgeConfirmationRequired`;

######################### V 8 - 2022-09-06 10:05:00
# Created vaers_foreign_report table.
CREATE TABLE `vaers_foreign_report` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `vaersId` varchar(45) NOT NULL,
  `aEDescription` longtext NOT NULL,
  `vaccinesListed` json NOT NULL,
  `vaersSex` int(11) NOT NULL,
  `vaersSexFixed` int(11) DEFAULT NULL,
  `cdcStateId` int(11) DEFAULT NULL,
  `onsetDate` varchar(45) DEFAULT NULL,
  `onsetDateFixed` varchar(45) DEFAULT NULL,
  `deceasedDate` varchar(45) DEFAULT NULL,
  `deceasedDateFixed` varchar(45) DEFAULT NULL,
  `vaccinationDate` varchar(45) DEFAULT NULL,
  `vaccinationDateFixed` varchar(45) DEFAULT NULL,
  `vaersReceptionDate` varchar(45) NOT NULL,
  `patientAge` double DEFAULT NULL,
  `patientAgeFixed` double DEFAULT NULL,
  `symptomsListed` json NOT NULL,
  `hospitalized` bit(1) NOT NULL,
  `hospitalizedFixed` bit(1) NOT NULL,
  `permanentDisability` bit(1) NOT NULL,
  `permanentDisabilityFixed` bit(1) NOT NULL,
  `lifeThreatning` bit(1) NOT NULL,
  `lifeThreatningFixed` bit(1) NOT NULL,
  `patientDied` bit(1) NOT NULL,
  `patientDiedFixed` bit(1) NOT NULL,
  `creationTimestamp` int(11) NOT NULL,
  `patientAgeConfirmation` int(11) DEFAULT NULL,
  `patientAgeConfirmationTimestamp` int(11) DEFAULT NULL,
  `userId` int(11) DEFAULT NULL,
  `patientAgeConfirmationRequired` bit(1) NOT NULL DEFAULT b'0',
  `hoursBetweenVaccineAndAE` double DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `vaers_foreign_report_unique` (`vaersId`),
  KEY `vaers_foreign_report_to_cdc_state_idx` (`cdcStateId`),
  KEY `vaers_foreign_report_to_user_idx` (`userId`),
  CONSTRAINT `vaers_foreign_report_to_cdc_state` FOREIGN KEY (`cdcStateId`) REFERENCES `cdc_state` (`id`),
  CONSTRAINT `vaers_foreign_report_to_user` FOREIGN KEY (`userId`) REFERENCES `user` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_vaers_foreign_report_insert` 
BEFORE INSERT ON `vaers_foreign_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`vaers_foreign_report` 
DROP FOREIGN KEY `vaers_foreign_report_to_cdc_state`;
ALTER TABLE `openvaet`.`vaers_foreign_report` 
DROP INDEX `vaers_foreign_report_to_cdc_state_idx` ;
ALTER TABLE `openvaet`.`vaers_foreign_report` 
CHANGE COLUMN `cdcStateId` `immProjectNumber` VARCHAR(45) NULL DEFAULT NULL ;

######################### V 9 - 2022-09-06 10:05:00
# Created vaers_foreign_report table.
CREATE TABLE `openvaet`.`country` (
  `id` INT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `population` INT NOT NULL,
  `isoCode2` VARCHAR(2) NULL,
  `creationTimestamp` INT NOT NULL,
  `populationUpdateTimestamp` INT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_country_insert` 
BEFORE INSERT ON `country` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (1,'Afghanistan',27657145,'AF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (2,'Aland Islands',28875,'AX');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (3,'Albania',2886026,'AL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (4,'Algeria',40400000,'DZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (5,'American Samoa',57100,'AS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (6,'Andorra',78014,'AD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (7,'Angola',25868000,'AO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (8,'Anguilla',13452,'AI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (9,'Antarctica',1000,'AQ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (10,'Antigua and Barbuda',86295,'AG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (11,'Argentina',43590400,'AR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (12,'Armenia',2994400,'AM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (13,'Aruba',107394,'AW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (14,'Australia',24117360,'AU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (15,'Austria',8725931,'AT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (16,'Azerbaijan',9730500,'AZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (17,'Bahamas',378040,'BS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (18,'Bahrain',1404900,'BH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (19,'Bangladesh',161006790,'BD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (20,'Barbados',285000,'BB');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (21,'Belarus',9498700,'BY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (22,'Belgium',11319511,'BE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (23,'Belize',370300,'BZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (24,'Benin',10653654,'BJ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (25,'Bermuda',61954,'BM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (26,'Bhutan',775620,'BT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (27,'Bolivia',10985059,'BO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (28,'Bonaire, Sint Eustatius and Saba',17408,'BQ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (29,'Bosnia and Herzegovina',3531159,'BA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (30,'Botswana',2141206,'BW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (31,'Bouvet Island',0,'BV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (32,'Brazil',206135893,'BR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (33,'British Indian Ocean Territory',3000,'IO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (34,'Brunei Darussalam',411900,'BN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (35,'Bulgaria',7153784,'BG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (36,'Burkina Faso',19034397,'BF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (37,'Burundi',10114505,'BI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (38,'Cabo Verde',531239,'CV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (39,'Cambodia',15626444,'KH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (40,'Cameroon',22709892,'CM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (41,'Canada',36155487,'CA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (42,'Cayman Islands',58238,'KY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (43,'Central African Republic',4998000,'CF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (44,'Chad',14497000,'TD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (45,'Chile',18191900,'CL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (46,'China',1377422166,'CN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (47,'Christmas Island',2072,'CX');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (48,'Cocos (Keeling) Islands',550,'CC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (49,'Colombia',48759958,'CO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (50,'Comoros',806153,'KM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (51,'Congo',4741000,'CG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (52,'Congo (Democratic Republic of the)',85026000,'CD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (53,'Cook Islands',18100,'CK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (54,'Costa Rica',4890379,'CR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (55,'Ivory Coast',22671331,'CI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (56,'Croatia',4190669,'HR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (57,'Cuba',11239004,'CU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (58,'Curacao',154843,'CW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (59,'Cyprus',847000,'CY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (60,'Czech Republic',10558524,'CZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (61,'Denmark',5717014,'DK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (62,'Djibouti',900000,'DJ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (63,'Dominica',71293,'DM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (64,'Dominican Republic',10075045,'DO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (65,'Ecuador',16545799,'EC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (66,'Egypt',91290000,'EG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (67,'El Salvador',6520675,'SV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (68,'Equatorial Guinea',1222442,'GQ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (69,'Eritrea',5352000,'ER');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (70,'Estonia',1315944,'EE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (71,'Ethiopia',92206005,'ET');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (72,'Falkland Islands (Malvinas)',2563,'FK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (73,'Faroe Islands',49376,'FO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (74,'Fiji',867000,'FJ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (75,'Finland',5491817,'FI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (76,'France',66710000,'FR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (77,'French Guiana',254541,'GF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (78,'French Polynesia',271800,'PF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (79,'French Southern Territories',140,'TF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (80,'Gabon',1802278,'GA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (81,'Gambia',1882450,'GM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (82,'Georgia',3720400,'GE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (83,'Germany',81770900,'DE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (84,'Ghana',27670174,'GH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (85,'Gibraltar',33140,'GI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (86,'Greece',10858018,'GR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (87,'Greenland',55847,'GL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (88,'Grenada',103328,'GD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (89,'Guadeloupe',400132,'GP');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (90,'Guam',184200,'GU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (91,'Guatemala',16176133,'GT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (92,'Guernsey',62999,'GG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (93,'Guinea',12947000,'GN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (94,'Guinea-Bissau',1547777,'GW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (95,'Guyana',746900,'GY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (96,'Haiti',11078033,'HT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (97,'Heard Island and McDonald Islands',0,'HM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (98,'Vatican City',1000,'VA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (99,'Honduras',8576532,'HN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (100,'Hong Kong',7324300,'HK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (101,'Hungary',9823000,'HU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (102,'Iceland',334300,'IS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (103,'India',1295210000,'IN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (104,'Indonesia',258705000,'ID');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (105,'Iran',79369900,'IR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (106,'Iraq',37883543,'IQ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (107,'Ireland',6378000,'IE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (108,'Isle of Man',84497,'IM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (109,'Israel',8527400,'IL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (110,'Italy',60665551,'IT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (111,'Jamaica',2723246,'JM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (112,'Japan',126960000,'JP');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (113,'Jersey',100800,'JE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (114,'Jordan',9531712,'JO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (115,'Kazakhstan',17753200,'KZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (116,'Kenya',47251000,'KE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (117,'Kiribati',113400,'KI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (118,'Korea (North - Democratic People\'s Republic of)',25281000,'KP');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (119,'Korea (South - Republic of)',50801405,'KR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (120,'Kuwait',4183658,'KW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (121,'Kyrgyzstan',6047800,'KG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (122,'Laos',6492400,'LA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (123,'Latvia',1961600,'LV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (124,'Lebanon',5988000,'LB');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (125,'Lesotho',1894194,'LS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (126,'Liberia',4615000,'LR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (127,'Libya',6385000,'LY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (128,'Liechtenstein',37623,'LI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (129,'Lithuania',2872294,'LT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (130,'Luxembourg',576200,'LU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (131,'Macao',649100,'MO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (132,'North Macedonia',2058539,'MK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (133,'Madagascar',22434363,'MG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (134,'Malawi',16832910,'MW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (135,'Malaysia',31405416,'MY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (136,'Maldives',344023,'MV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (137,'Mali',18135000,'ML');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (138,'Malta',425384,'MT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (139,'Marshall Islands',54880,'MH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (140,'Martinique',378243,'MQ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (141,'Mauritania',3718678,'MR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (142,'Mauritius',1262879,'MU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (143,'Mayotte',226915,'YT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (144,'Mexico',122273473,'MX');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (145,'Northern Ireland',1885400,NULL);
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (146,'Moldova',3553100,'MD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (147,'Monaco',38400,'MC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (148,'Mongolia',3093100,'MN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (149,'Montenegro',621810,'ME');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (150,'Montserrat',4922,'MS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (151,'Morocco',33337529,'MA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (152,'Mozambique',26423700,'MZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (153,'Myanmar',51419420,'MM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (154,'Namibia',2324388,'NA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (155,'Nauru',10084,'NR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (156,'Nepal',28431500,'NP');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (157,'Netherlands',17019800,'NL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (158,'New Caledonia',268767,'NC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (159,'New Zealand',4697854,'NZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (160,'Nicaragua',6262703,'NI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (161,'Niger',20715000,'NE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (162,'Nigeria',186988000,'NG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (163,'Niue',1470,'NU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (164,'Norfolk Island',2302,'NF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (165,'Northern Mariana Islands',56940,'MP');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (166,'Norway',5223256,'NO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (167,'Oman',4420133,'OM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (168,'Pakistan',194125062,'PK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (169,'Palau',17950,'PW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (170,'Palestine, State of',4682467,'PS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (171,'Panama',3814672,'PA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (172,'Papua New Guinea',8083700,'PG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (173,'Paraguay',6854536,'PY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (174,'Peru',31488700,'PE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (175,'Philippines',103279800,'PH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (176,'Pitcairn Islands',56,'PN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (177,'Poland',38437239,'PL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (178,'Portugal',10374822,'PT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (179,'Puerto Rico',3474182,'PR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (180,'Qatar',2587564,'QA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (181,'Republic of Kosovo',1733842,'XK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (182,'Reunion',840974,'RE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (183,'Romania',19861408,'RO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (184,'Russian Federation',146599183,'RU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (185,'Rwanda',11553188,'RW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (186,'Saint Barthelemy',9417,'BL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (187,'Saint Helena, Ascension and Tristan da Cunha',4255,'SH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (188,'Saint Kitts and Nevis',46204,'KN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (189,'Saint Lucia',186000,'LC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (190,'Saint Martin (French part)',36979,'MF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (191,'Saint Pierre and Miquelon',6069,'PM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (192,'Saint Vincent and the Grenadines',109991,'VC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (193,'Samoa',194899,'WS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (194,'San Marino',33005,'SM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (195,'Sao Tome and Principe',187356,'ST');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (196,'Saudi Arabia',32248200,'SA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (197,'Senegal',14799859,'SN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (198,'Serbia',7076372,'RS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (199,'Seychelles',91400,'SC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (200,'Sierra Leone',7075641,'SL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (201,'Singapore',5535000,'SG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (202,'Sint Maarten (Dutch part)',38247,'SX');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (203,'Slovakia',5426252,'SK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (204,'Slovenia',2064188,'SI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (205,'Solomon Islands',642000,'SB');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (206,'Somalia',11079000,'SO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (207,'South Africa',55653654,'ZA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (208,'South Georgia and the South Sandwich Islands',30,'GS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (209,'South Sudan',12131000,'SS');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (210,'Spain',46438422,'ES');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (211,'Sri Lanka',20966000,'LK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (212,'Sudan',39598700,'SD');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (213,'Suriname',541638,'SR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (214,'Svalbard and Jan Mayen',2562,'SJ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (215,'Swaziland',1132657,'SZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (216,'Sweden',9894888,'SE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (217,'Switzerland',8341600,'CH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (218,'Syria',18564000,'SY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (219,'Taiwan',23503349,'TW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (220,'Tajikistan',8593600,'TJ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (221,'Tanzania',55155000,'TZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (222,'Thailand',65327652,'TH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (223,'Timor-Leste',1167242,'TL');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (224,'Togo',7143000,'TG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (225,'Tokelau',1411,'TK');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (226,'Tonga',103252,'TO');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (227,'Trinidad and Tobago',1349667,'TT');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (228,'Tunisia',11154400,'TN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (229,'Turkey',78741053,'TR');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (230,'Turkmenistan',4751120,'TM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (231,'Turks and Caicos Islands',31458,'TC');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (232,'Tuvalu',10640,'TV');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (233,'Uganda',33860700,'UG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (234,'Ukraine',42692393,'UA');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (235,'United Arab Emirates',9856000,'AE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (236,'United Kingdom of Great Britain and Northern Ireland',65110000,'GB');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (237,'United States Minor Outlying Islands',300,'UM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (238,'United States of America',323947000,'US');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (239,'Uruguay',3480222,'UY');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (240,'Uzbekistan',31576400,'UZ');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (241,'Vanuatu',277500,'VU');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (242,'Venezuela',31028700,'VE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (243,'Viet Nam',92700000,'VN');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (244,'Virgin Islands (British)',28514,'VG');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (245,'Virgin Islands (U.S.)',114743,'VI');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (246,'Wallis and Futuna',11750,'WF');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (247,'Western Sahara',510713,'EH');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (248,'Yemen',27478000,'YE');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (249,'Zambia',15933883,'ZM');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (250,'Zimbabwe',14240168,'ZW');
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (251,'Scotland',5424000,NULL);
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (252,'Wales',3125000,NULL);
INSERT INTO `country` (`id`,`name`,`population`,`isoCode2`) VALUES (253,'Federal States Of Micronesia',112640,'FM');

# Created table country_state.
CREATE TABLE `openvaet`.`country_state` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `countryId` INT NOT NULL,
  `name` VARCHAR(250) NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`));
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_country_state_insert` 
BEFORE INSERT ON `country_state` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added known reports to country & country_state
ALTER TABLE `openvaet`.`country_state` 
ADD COLUMN `reportsArchived` INT NOT NULL DEFAULT 0 AFTER `name`;
ALTER TABLE `openvaet`.`country` 
ADD COLUMN `reportsArchived` INT NOT NULL DEFAULT 0 AFTER `populationUpdateTimestamp`;
ALTER TABLE `openvaet`.`country_state` 
ADD COLUMN `cdcCode2` VARCHAR(2) NOT NULL AFTER `creationTimestamp`,
ADD COLUMN `alphaCode2` VARCHAR(2) NOT NULL AFTER `cdcCode2`;
ALTER TABLE `openvaet`.`country_state` 
CHANGE COLUMN `alphaCode2` `alphaCode2` VARCHAR(2) NULL ;
ALTER TABLE `openvaet`.`country_state` 
DROP COLUMN `reportsArchived`;
ALTER TABLE `openvaet`.`country` 
DROP COLUMN `reportsArchived`;

# Added country states.
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (1,238,'Wisconsin',1663289136,'47','WI');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (2,238,'Texas',1663289157,'41','TX');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (3,238,'New York',1663289157,'30','NY');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (4,238,'Oklahoma',1663289157,'34','OK');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (5,238,'Ohio',1663289157,'33','OH');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (6,238,'Oregon',1663289157,'35','OR');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (7,238,'Kentucky',1663289157,'15','KY');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (8,238,'Florida',1663289157,'08','FL');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (9,238,'North Dakota',1663289157,'32','ND');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (10,238,'South Carolina',1663289157,'38','SC');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (11,238,'Georgia',1663289157,'09','GA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (12,238,'Colorado',1663289157,'05','CO');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (13,238,'North Carolina',1663289157,'31','NC');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (14,238,'Maryland',1663289157,'18','MD');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (15,238,'Pennsylvania',1663289157,'36','PA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (16,238,'New Hampshire',1663289157,'27','NH');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (17,238,'Washington',1663289157,'45','WA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (18,238,'Tennessee',1663289157,'40','TN');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (19,238,'Unknown',1663289157,'00',NULL);
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (20,238,'Illinois',1663289157,'11','IL');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (21,238,'Michigan',1663289157,'20','MI');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (22,238,'California',1663289157,'04','CA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (23,238,'Indiana',1663289157,'12','IN');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (24,238,'Arkansas',1663289157,'03','AR');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (25,238,'Minnesota',1663289157,'21','MN');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (26,238,'Mississippi',1663289157,'22','MS');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (27,238,'South Dakota',1663289157,'39','SD');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (28,238,'Maine',1663289157,'17','ME');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (29,238,'New Jersey',1663289157,'28','NJ');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (30,238,'Nebraska',1663289157,'25','NE');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (31,238,'Delaware',1663289157,'07','DE');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (32,238,'Utah',1663289157,'42','UT');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (33,238,'Arizona',1663289158,'02','AZ');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (34,238,'Connecticut',1663289158,'06','CT');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (35,238,'Virginia',1663289158,'44','VA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (36,238,'West Virginia',1663289158,'46','WV');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (37,238,'Iowa',1663289158,'13','IA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (38,238,'Kansas',1663289158,'14','KS');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (39,238,'Missouri',1663289158,'23','MO');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (40,238,'Alabama',1663289158,'01','AL');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (41,238,'Wyoming',1663289158,'48','WY');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (42,238,'Vermont',1663289158,'43','VT');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (43,238,'Massachusetts',1663289158,'19','MA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (44,238,'Montana',1663289158,'24','MT');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (45,238,'Louisiana',1663289158,'16','LA');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (46,238,'New Mexico',1663289158,'29','NM');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (47,238,'Idaho',1663289158,'10','ID');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (48,238,'Rhode Island',1663289158,'37','RI');
INSERT INTO `country_state` (`id`,`countryId`,`name`,`creationTimestamp`,`cdcCode2`,`alphaCode2`) VALUES (49,238,'Nevada',1663289158,'26','NV');

# Created manufacturer table.
CREATE TABLE `manufacturer` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_manufacturer_insert` 
BEFORE INSERT ON `manufacturer` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created sex table.
CREATE TABLE `sex` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shortName` varchar(250) NOT NULL,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_sex_insert` 
BEFORE INSERT ON `sex` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
INSERT INTO `openvaet`.`sex` (`id`, `shortName`, `name`) VALUES ('1', 'F', 'Female');
INSERT INTO `openvaet`.`sex` (`id`, `shortName`, `name`) VALUES ('2', 'M', 'Male');
INSERT INTO `openvaet`.`sex` (`id`, `shortName`, `name`) VALUES ('3', 'U', 'Unknown');

# Created symptom table.
CREATE TABLE `symptom` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  PRIMARY KEY (`id`)
);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_symptom_insert` 
BEFORE INSERT ON `symptom` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created symptoms_set table.
CREATE TABLE `symptoms_set` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  `symptoms` JSON DEFAULT NULL,
  `changelog` JSON DEFAULT NULL,
  PRIMARY KEY (`id`)
);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_symptoms_set_insert` 
BEFORE INSERT ON `symptoms_set` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`symptoms_set` 
ADD COLUMN `userId` INT NOT NULL AFTER `changelog`,
ADD INDEX `symptoms_set_to_user_idx` (`userId` ASC);
ALTER TABLE `openvaet`.`symptoms_set` 
ADD CONSTRAINT `symptoms_set_to_user`
  FOREIGN KEY (`userId`)
  REFERENCES `openvaet`.`user` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`symptoms_set` 
DROP COLUMN `changelog`;
ALTER TABLE `openvaet`.`symptom` 
ADD UNIQUE INDEX `symptom_unique_name` (`name` ASC);

# Inserting default symptoms & symptomps sets.
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (1,'Abortion',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (2,'Abortion complete',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (3,'Abortion incomplete',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (4,'Abortion induced',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (5,'Abortion missed',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (6,'Abortion of ectopic pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (7,'Abortion spontaneous',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (8,'Abortion spontaneous complete',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (9,'Abortion spontaneous incomplete',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (10,'Abortion threatened',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (11,'Amniocentesis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (12,'Amniotic cavity infection',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (13,'Amniotic fluid index decreased',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (14,'Amniotic membrane rupture test positive',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (15,'Anembryonic gestation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (16,'Bradycardia foetal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (17,'Caesarean section',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (18,'Cerebral haemorrhage foetal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (19,'Cleft lip',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (20,'Cleft lip and palate',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (21,'Complication of pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (22,'Ectopic pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (23,'Expired product administered',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (24,'Exposure during pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (25,'Failed induction of labour',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (26,'First trimester pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (27,'Foetal cardiac arrest',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (28,'Foetal cardiac disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (29,'Foetal chromosome abnormality',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (30,'Foetal cystic hygroma',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (31,'Foetal death',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (32,'Foetal disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (33,'Foetal exposure during pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (34,'Foetal growth abnormality',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (35,'Foetal growth restriction',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (36,'Foetal heart rate abnormal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (37,'Foetal hypokinesia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (38,'Foetal monitoring',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (39,'Foetal non-stress test',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (40,'Foetal non-stress test normal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (41,'Foetal placental thrombosis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (42,'Foetal renal impairment',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (43,'Gestational hypertension',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (44,'Haemorrhage in pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (45,'Human chorionic gonadotropin increased',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (46,'Hydrops foetalis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (47,'Inappropriate schedule of product administration',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (48,'Incorrect dose administered',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (49,'Incorrect dose administered by device',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (50,'Incorrect dose administered by product',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (51,'Induced abortion failed',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (52,'Induced labour',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (53,'Interchange of vaccine products',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (54,'Labour induction',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (55,'Low birth weight baby',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (56,'Maternal exposure before pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (57,'Maternal exposure during pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (58,'Maternal exposure timing unspecified',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (59,'Medication dilution',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (60,'Medication error',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (61,'Needle issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (62,'Placental disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (63,'Placental insufficiency',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (64,'Post abortion haemorrhage',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (65,'Pregnancy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (66,'Pregnancy test positive',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (67,'Premature baby',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (68,'Premature baby death',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (69,'Premature delivery',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (70,'Premature labour',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (71,'Premature rupture of membranes',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (72,'Premature separation of placenta',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (73,'Prenatal screening test',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (74,'Preterm premature rupture of membranes',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (75,'Primiparous',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (76,'Product administered at inappropriate site',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (77,'Product administered by wrong person',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (78,'Product administered to patient of inappropriate age',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (79,'Product administration error',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (80,'Product administration interrupted',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (81,'Product container issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (82,'Product container seal issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (83,'Product contamination',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (84,'Product contamination chemical',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (85,'Product contamination microbial',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (86,'Product contamination physical',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (87,'Product delivery mechanism issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (88,'Product design issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (89,'Product dispensing error',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (90,'Product dispensing issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (91,'Product expiration date issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (92,'Product label on wrong product',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (93,'Product packaging confusion',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (94,'Product packaging issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (95,'Product preparation issue',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (96,'Product storage error',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (97,'Stillbirth',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (98,'Tachycardia foetal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (99,'Ultrasound antenatal screen abnormal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (100,'Ultrasound antenatal screen normal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (101,'Ultrasound foetal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (102,'Ultrasound foetal abnormal',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (103,'Umbilical cord abnormality',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (104,'Umbilical cord around neck',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (105,'Unevaluable event',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (106,'Uterine dilation and curettage',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (107,'Uterine dilation and evacuation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (108,'Wrong product administered',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (109,'Wrong technique in product usage process',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (110,'Abasia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (111,'Accidental overdose',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (112,'Acute coronary syndrome',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (113,'Acute pulmonary oedema',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (114,'Acute respiratory distress syndrome',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (115,'Acute respiratory failure',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (116,'Acute stress disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (117,'Adverse event',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (118,'Adverse event following immunisation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (119,'Adverse reaction',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (120,'Allergic cough',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (121,'Allergy test positive',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (122,'Allergy to vaccine',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (123,'Altered state of consciousness',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (124,'Anaphylactic reaction',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (125,'Anaphylactic shock',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (126,'Anaphylactoid reaction',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (127,'Anticonvulsant drug level therapeutic',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (128,'Aphonia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (129,'Apnoea',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (130,'Apnoeic attack',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (131,'Apparent death',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (132,'Apparent life threatening event',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (133,'Arrhythmia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (134,'Arrhythmia supraventricular',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (135,'Asphyxia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (136,'Asterixis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (137,'Ataxia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (138,'Atonic seizures',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (139,'Atrial fibrillation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (140,'Atrial flutter',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (141,'Autonomic nervous system imbalance',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (142,'Balance disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (143,'Bronchospasm',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (144,'Cardiac arrest',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (145,'Cardiac failure',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (146,'Cardiac failure acute',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (147,'Cardiac fibrillation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (148,'Cardiac flutter',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (149,'Cardiac murmur',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (150,'Cardiogenic shock',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (151,'Cardiovascular insufficiency',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (152,'Cheilitis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (153,'Choking',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (154,'Choking sensation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (155,'Circulatory collapse',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (156,'Clonic convulsion',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (157,'Clonus',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (158,'Confusional state',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (159,'Consciousness fluctuating',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (160,'Contraindicated product administered',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (161,'Contraindication to vaccination',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (162,'Contusion',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (163,'Conversion disorder',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (164,'Cyanosis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (165,'Cyclic vomiting syndrome',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (166,'Death',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (167,'Decorticate posture',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (168,'Decreased activity',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (169,'Depressed level of consciousness',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (170,'Disorganised speech',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (171,'Disorientation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (172,'Dissociation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (173,'Disturbance in attention',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (174,'Dizziness',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (175,'Dizziness postural',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (176,'Drug hypersensitivity',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (177,'Drug intolerance',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (178,'Dysarthria',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (179,'Dysgeusia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (180,'Dysphagia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (181,'Dysphonia',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (182,'Dyspnoea',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (183,'Dyspnoea exertional',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (184,'Electric shock sensation',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (185,'Enlarged uvula',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (186,'Epilepsy',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (187,'Epistaxis',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (188,'Essential tremor',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (189,'Exaggerated startle response',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (190,'Exploding head syndrome',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (191,'Eye swelling',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (192,'Face oedema',1663298071);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (193,'Facial discomfort',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (194,'Facial pain',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (195,'Facial paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (196,'Facial paresis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (197,'Facial spasm',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (198,'Febrile convulsion',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (199,'Feeling abnormal',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (200,'Feeling of despair',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (201,'Floppy infant',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (202,'Foaming at mouth',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (203,'Focal dyscognitive seizures',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (204,'Gait disturbance',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (205,'Gait inability',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (206,'Gaze palsy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (207,'Generalised tonic-clonic seizure',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (208,'Gross motor delay',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (209,'Grunting',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (210,'Heart rate',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (211,'Heart rate abnormal',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (212,'Heart rate decreased',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (213,'Heart rate increased',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (214,'Heart rate irregular',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (215,'Hypersensitivity',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (216,'Hypersensitivity pneumonitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (217,'Hypersensitivity vasculitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (218,'Hypertensive crisis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (219,'Hypertonia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (220,'Hyperventilation',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (221,'Hypoglossal nerve disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (222,'Hyporesponsive to stimuli',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (223,'Hypotension',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (224,'Hypotonia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (225,'Hypotonic-hyporesponsive episode',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (226,'Hypoxia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (227,'IVth nerve paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (228,'Immediate post-injection reaction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (229,'Immobile',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (230,'Incoherent',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (231,'Infantile apnoea',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (232,'Infantile back arching',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (233,'Infantile spasms',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (234,'Injection site necrosis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (235,'Intermittent positive pressure breathing',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (236,'Iridocyclitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (237,'Irregular breathing',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (238,'Ischaemic stroke',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (239,'Juvenile myoclonic epilepsy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (240,'Lacrimation increased',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (241,'Laryngitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (242,'Laryngomalacia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (243,'Laryngospasm',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (244,'Lethargy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (245,'Life support',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (246,'Lip erythema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (247,'Lip haemorrhage',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (248,'Lip injury',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (249,'Lip oedema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (250,'Lip swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (251,'Lip ulceration',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (252,'Listless',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (253,'Loss of consciousness',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (254,'Metal poisoning',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (255,'Motor dysfunction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (256,'Mouth swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (257,'Mouth ulceration',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (258,'Movement disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (259,'Muscle contractions involuntary',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (260,'Muscle contracture',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (261,'Muscle rigidity',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (262,'Muscle spasms',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (263,'Muscle spasticity',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (264,'Muscle twitching',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (265,'Mutism',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (266,'Mydriasis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (267,'Myoclonic epilepsy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (268,'Nasopharyngitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (269,'Nausea',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (270,'Near death experience',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (271,'Nervous system disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (272,'Obstructive airways disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (273,'Oesophageal spasm',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (274,'Opisthotonus',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (275,'Oropharyngeal pain',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (276,'Orthopnoea',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (277,'Orthostatic hypotension',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (278,'Palatal swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (279,'Pallor',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (280,'Palpitations',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (281,'Panic attack',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (282,'Panic disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (283,'Panic reaction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (284,'Paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (285,'Paraplegia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (286,'Partial seizures',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (287,'Periorbital cellulitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (288,'Periorbital oedema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (289,'Periorbital swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (290,'Petit mal epilepsy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (291,'Pharyngeal erythema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (292,'Pharyngeal haemorrhage',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (293,'Pharyngeal hypoaesthesia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (294,'Pharyngeal inflammation',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (295,'Pharyngeal oedema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (296,'Pharyngeal swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (297,'Pharyngitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (298,'Photophobia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (299,'Photopsia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (300,'Photosensitivity reaction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (301,'Phrenic nerve paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (302,'Postictal state',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (303,'Presyncope',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (304,'Pulse abnormal',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (305,'Pulse absent',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (306,'Pulseless electrical activity',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (307,'Pupil fixed',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (308,'Pupillary reflex impaired',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (309,'Quadriplegia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (310,'Radial nerve palsy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (311,'Respiration abnormal',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (312,'Respiratory arrest',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (313,'Respiratory depression',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (314,'Respiratory disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (315,'Respiratory distress',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (316,'Respiratory failure',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (317,'Respiratory rate',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (318,'Respiratory rate increased',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (319,'Respiratory symptom',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (320,'Respiratory tract congestion',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (321,'Resuscitation',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (322,'Retching',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (323,'Screaming',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (324,'Seizure',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (325,'Seizure cluster',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (326,'Seizure like phenomena',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (327,'Sensory disturbance',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (328,'Sensory loss',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (329,'Septic shock',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (330,'Severe myoclonic epilepsy of infancy',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (331,'Shock',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (332,'Shock symptom',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (333,'Sinus arrest',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (334,'Sinus arrhythmia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (335,'Skin test',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (336,'Skin test positive',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (337,'Slow response to stimuli',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (338,'Slow speech',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (339,'Sluggishness',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (340,'Sneezing',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (341,'Somnolence',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (342,'Speech disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (343,'Speech disorder developmental',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (344,'Staring',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (345,'Status epilepticus',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (346,'Stridor',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (347,'Sudden death',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (348,'Sudden infant death syndrome',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (349,'Sudden onset of sleep',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (350,'Supraventricular extrasystoles',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (351,'Supraventricular tachycardia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (352,'Swelling',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (353,'Swelling face',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (354,'Swelling of eyelid',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (355,'Swollen tongue',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (356,'Syncope',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (357,'Tachycardia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (358,'Tachypnoea',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (359,'Tardive dyskinesia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (360,'Taste disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (361,'Throat clearing',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (362,'Throat tightness',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (363,'Tonic clonic movements',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (364,'Tonic convulsion',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (365,'Torsade de pointes',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (366,'Transient global amnesia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (367,'Transient ischaemic attack',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (368,'Tremor',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (369,'Trigeminal neuralgia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (370,'Tunnel vision',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (371,'Type III immune complex mediated reaction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (372,'Type IV hypersensitivity reaction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (373,'Unresponsive to stimuli',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (374,'Upper airway obstruction',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (375,'VIIth nerve injury',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (376,'VIIth nerve paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (377,'VIth nerve paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (378,'Vaccination complication',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (379,'Vaccination site discomfort',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (380,'Vaccination site erythema',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (381,'Vaccination site hypersensitivity',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (382,'Vaccination site necrosis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (383,'Vaccination site pain',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (384,'Vagus nerve disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (385,'Ventricular arrhythmia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (386,'Ventricular extrasystoles',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (387,'Ventricular fibrillation',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (388,'Ventricular tachycardia',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (389,'Vertigo',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (390,'Vertigo positional',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (391,'Vestibular disorder',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (392,'Vestibular migraine',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (393,'Vestibular neuronitis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (394,'Vision blurred',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (395,'Vocal cord paralysis',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (396,'Vomiting',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (397,'Vomiting projectile',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (398,'Walking disability',1663298072);
INSERT INTO `symptom` (`id`,`name`,`creationTimestamp`) VALUES (399,'Wheezing',1663298072);
INSERT INTO `symptoms_set` (`id`,`name`,`creationTimestamp`,`symptoms`,`userId`) VALUES (1,'Anaphylaxis symptoms',1663298612,'[\"110\", \"111\", \"112\", \"113\", \"114\", \"115\", \"116\", \"117\", \"118\", \"119\", \"120\", \"121\", \"122\", \"123\", \"124\", \"125\", \"126\", \"127\", \"128\", \"129\", \"130\", \"131\", \"132\", \"133\", \"134\", \"135\", \"136\", \"137\", \"138\", \"139\", \"140\", \"141\", \"142\", \"143\", \"144\", \"145\", \"146\", \"147\", \"148\", \"149\", \"150\", \"151\", \"152\", \"153\", \"154\", \"155\", \"156\", \"157\", \"158\", \"159\", \"160\", \"161\", \"162\", \"163\", \"164\", \"165\", \"166\", \"167\", \"168\", \"169\", \"170\", \"171\", \"172\", \"173\", \"174\", \"175\", \"176\", \"177\", \"178\", \"179\", \"180\", \"181\", \"182\", \"183\", \"184\", \"185\", \"186\", \"187\", \"188\", \"189\", \"190\", \"191\", \"192\", \"193\", \"194\", \"195\", \"196\", \"197\", \"198\", \"199\", \"200\", \"201\", \"202\", \"203\", \"204\", \"205\", \"206\", \"207\", \"208\", \"209\", \"210\", \"211\", \"212\", \"213\", \"214\", \"215\", \"216\", \"217\", \"218\", \"219\", \"220\", \"221\", \"222\", \"223\", \"224\", \"225\", \"226\", \"228\", \"229\", \"230\", \"231\", \"232\", \"233\", \"234\", \"235\", \"236\", \"237\", \"238\", \"227\", \"239\", \"240\", \"241\", \"242\", \"243\", \"244\", \"245\", \"246\", \"247\", \"248\", \"249\", \"250\", \"251\", \"252\", \"253\", \"254\", \"255\", \"256\", \"257\", \"258\", \"259\", \"260\", \"261\", \"262\", \"263\", \"264\", \"265\", \"266\", \"267\", \"268\", \"269\", \"270\", \"271\", \"272\", \"273\", \"274\", \"275\", \"276\", \"277\", \"278\", \"279\", \"280\", \"281\", \"282\", \"283\", \"284\", \"285\", \"286\", \"287\", \"288\", \"289\", \"290\", \"291\", \"292\", \"293\", \"294\", \"295\", \"296\", \"297\", \"298\", \"299\", \"300\", \"301\", \"302\", \"303\", \"78\", \"304\", \"305\", \"306\", \"307\", \"308\", \"309\", \"310\", \"311\", \"312\", \"313\", \"314\", \"315\", \"316\", \"317\", \"318\", \"319\", \"320\", \"321\", \"322\", \"323\", \"324\", \"325\", \"326\", \"327\", \"328\", \"329\", \"330\", \"331\", \"332\", \"333\", \"334\", \"335\", \"336\", \"337\", \"338\", \"339\", \"340\", \"341\", \"342\", \"343\", \"344\", \"345\", \"346\", \"347\", \"348\", \"349\", \"350\", \"351\", \"352\", \"353\", \"354\", \"355\", \"356\", \"357\", \"358\", \"359\", \"360\", \"361\", \"362\", \"363\", \"364\", \"365\", \"366\", \"367\", \"368\", \"369\", \"370\", \"371\", \"372\", \"373\", \"374\", \"378\", \"379\", \"380\", \"381\", \"382\", \"383\", \"384\", \"385\", \"386\", \"387\", \"388\", \"389\", \"390\", \"391\", \"392\", \"393\", \"375\", \"376\", \"394\", \"377\", \"395\", \"396\", \"397\", \"398\", \"399\"]',2);
INSERT INTO `symptoms_set` (`id`,`name`,`creationTimestamp`,`symptoms`,`userId`) VALUES (2,'Foetal Deaths Related',1663298612,'[\"1\", \"2\", \"3\", \"4\", \"5\", \"6\", \"7\", \"8\", \"9\", \"22\", \"31\", \"51\", \"64\", \"68\", \"97\"]',1);
INSERT INTO `symptoms_set` (`id`,`name`,`creationTimestamp`,`symptoms`,`userId`) VALUES (3,'Indicators of Administration Errors',1663298612,'[\"23\", \"47\", \"48\", \"49\", \"50\", \"53\", \"59\", \"60\", \"61\", \"76\", \"77\", \"78\", \"79\", \"80\", \"81\", \"82\", \"83\", \"84\", \"85\", \"86\", \"87\", \"88\", \"89\", \"90\", \"91\", \"92\", \"93\", \"94\", \"95\", \"96\", \"105\", \"108\", \"109\"]',1);
INSERT INTO `symptoms_set` (`id`,`name`,`creationTimestamp`,`symptoms`,`userId`) VALUES (4,'Pregnancy Complications Related',1663298612,'[\"1\", \"2\", \"3\", \"4\", \"5\", \"6\", \"7\", \"8\", \"9\", \"10\", \"12\", \"16\", \"18\", \"19\", \"20\", \"21\", \"22\", \"25\", \"27\", \"28\", \"29\", \"30\", \"32\", \"34\", \"35\", \"36\", \"37\", \"41\", \"42\", \"43\", \"44\", \"45\", \"46\", \"52\", \"54\", \"55\", \"58\", \"62\", \"63\", \"64\", \"67\", \"68\", \"69\", \"70\", \"71\", \"72\", \"74\", \"97\", \"98\", \"99\", \"102\", \"103\", \"104\", \"106\", \"107\"]',1);
INSERT INTO `symptoms_set` (`id`,`name`,`creationTimestamp`,`symptoms`,`userId`) VALUES (5,'Pregnancy Related',1663298612,'[\"1\", \"2\", \"3\", \"4\", \"5\", \"6\", \"7\", \"8\", \"9\", \"10\", \"11\", \"12\", \"13\", \"14\", \"15\", \"16\", \"17\", \"18\", \"19\", \"20\", \"21\", \"22\", \"24\", \"25\", \"26\", \"27\", \"28\", \"29\", \"30\", \"31\", \"32\", \"33\", \"34\", \"35\", \"36\", \"37\", \"38\", \"39\", \"40\", \"41\", \"42\", \"43\", \"44\", \"45\", \"46\", \"51\", \"52\", \"54\", \"55\", \"56\", \"57\", \"58\", \"62\", \"63\", \"64\", \"65\", \"66\", \"67\", \"68\", \"69\", \"70\", \"71\", \"72\", \"73\", \"74\", \"75\", \"97\", \"98\", \"99\", \"100\", \"101\", \"102\", \"103\", \"104\", \"106\", \"107\"]',1);

# Added unique constrain to symptom_set
ALTER TABLE `openvaet`.`symptoms_set` 
ADD UNIQUE INDEX `symptoms_set_unique_name` (`name` ASC);
ALTER TABLE `openvaet`.`symptoms_set` 
DROP INDEX `symptoms_set_unique_name` ,
ADD UNIQUE INDEX `symptoms_set_unique_name` (`name` ASC, `userId` ASC);

# Created keywords_set table.
CREATE TABLE `keywords_set` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `creationTimestamp` int NOT NULL,
  `keywords` JSON DEFAULT NULL,
  `changelog` JSON DEFAULT NULL,
  PRIMARY KEY (`id`)
);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_keywords_set_insert` 
BEFORE INSERT ON `keywords_set` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`keywords_set` 
ADD COLUMN `userId` INT NOT NULL AFTER `changelog`,
ADD INDEX `keywords_set_to_user_idx` (`userId` ASC);
ALTER TABLE `openvaet`.`keywords_set` 
ADD CONSTRAINT `keywords_set_to_user`
  FOREIGN KEY (`userId`)
  REFERENCES `openvaet`.`user` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`keywords_set` 
DROP COLUMN `changelog`;
ALTER TABLE `openvaet`.`keywords_set` 
ADD UNIQUE INDEX `keyword_unique_name` (`name` ASC);
ALTER TABLE `openvaet`.`keywords_set` 
CHANGE COLUMN `keywords` `keywords` LONGTEXT NULL DEFAULT NULL ;

# Created report table.
CREATE TABLE `report` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `vaersSource` int(11) NOT NULL,
  `countryId` int(11) DEFAULT NULL,
  `countryStateId` int(11) DEFAULT NULL,
  `vaersId` varchar(45) NOT NULL,
  `aEDescription` longtext NOT NULL,
  `vaccinesListed` json NOT NULL,
  `sex` int(11) NOT NULL,
  `sexFixed` int(11) DEFAULT NULL,
  `immProjectNumber` varchar(45) DEFAULT NULL,
  `onsetDate` varchar(45) DEFAULT NULL,
  `onsetDateFixed` varchar(45) DEFAULT NULL,
  `deceasedDate` varchar(45) DEFAULT NULL,
  `deceasedDateFixed` varchar(45) DEFAULT NULL,
  `vaccinationDate` varchar(45) DEFAULT NULL,
  `vaccinationDateFixed` varchar(45) DEFAULT NULL,
  `vaersReceptionDate` varchar(45) NOT NULL,
  `patientAge` double DEFAULT NULL,
  `patientAgeFixed` double DEFAULT NULL,
  `symptomsListed` json NOT NULL,
  `hospitalized` bit(1) NOT NULL,
  `hospitalizedFixed` bit(1) NOT NULL,
  `permanentDisability` bit(1) NOT NULL,
  `permanentDisabilityFixed` bit(1) NOT NULL,
  `lifeThreatning` bit(1) NOT NULL,
  `lifeThreatningFixed` bit(1) NOT NULL,
  `patientDied` bit(1) NOT NULL,
  `patientDiedFixed` bit(1) NOT NULL,
  `creationTimestamp` int(11) NOT NULL,
  `patientAgeConfirmation` int(11) DEFAULT NULL,
  `patientAgeConfirmationTimestamp` int(11) DEFAULT NULL,
  `patientAgeUserId` int(11) DEFAULT NULL,
  `patientAgeConfirmationRequired` bit(1) NOT NULL DEFAULT b'0',
  `hoursBetweenVaccineAndAE` double DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `report_unique` (`vaersId`),
  KEY `report_to_patientAgeUser_idx` (`patientAgeUserId`),
  CONSTRAINT `report_to_patientAgeUser` FOREIGN KEY (`patientAgeUserId`) REFERENCES `user` (`id`) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_report_insert` 
BEFORE INSERT ON `report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`report` 
ADD INDEX `report_to_country_idx` (`countryId` ASC),
ADD INDEX `report_to_country_state_idx` (`countryStateId` ASC);
ALTER TABLE `openvaet`.`report` 
ADD CONSTRAINT `report_to_country`
  FOREIGN KEY (`countryId`)
  REFERENCES `openvaet`.`country` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION,
ADD CONSTRAINT `report_to_country_state`
  FOREIGN KEY (`countryStateId`)
  REFERENCES `openvaet`.`country_state` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;
ALTER TABLE `openvaet`.`report` 
ADD INDEX `report_patientAgeConfirmation_idx` (`patientAgeConfirmation` ASC);
ALTER TABLE `openvaet`.`report` 
ADD INDEX `report_patientAgeConfirmationRequired_idx` (`patientAgeConfirmationRequired` ASC);
ALTER TABLE `openvaet`.`report` 
ADD INDEX `report_patientAgeConfirmationAndRequired_idx` (`patientAgeConfirmationRequired` ASC, `patientAgeConfirmation` ASC);

# Updated Foreign US state code.
UPDATE `openvaet`.`country_state` SET `alphaCode2` = 'FR' WHERE (`id` = '19');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('50', '238', 'Alaska', '99', 'AK');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('51', '238', 'Puerto Rico', '98', 'PR');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('52', '238', 'Hawai', '97', 'HI');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('53', '238', 'Guam', '96', 'GU');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('54', '238', 'American Samoa', '95', 'AS');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('55', '238', 'Baker Island', '94', 'XB');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('56', '238', 'U.S. Virgin Islands', '93', 'VI');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('57', '238', 'Northern Mariana Islands', '92', 'MP');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('58', '238', 'Marshall Islands', '91', 'MH');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('59', '238', 'Micronesia', '90', 'FM');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('60', '238', 'Palmyra Atoll', '89', 'XL');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('61', '238', 'Navassa Island', '88', 'XV');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('62', '238', 'Midway Islands', '87', 'QM');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('63', '238', 'Wake Island', '86', 'QW');
INSERT INTO `openvaet`.`country_state` (`id`, `countryId`, `name`, `cdcCode2`, `alphaCode2`) VALUES ('64', '238', 'Palau', '85', 'PW');

# Created report table.
CREATE TABLE `openvaet`.`wizard_report` (
  `id` INT NOT NULL,
  `reportId` INT NOT NULL,
  `creationTimestamp` INT NOT NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `wizard_report_to_report`
    FOREIGN KEY (`reportId`)
    REFERENCES `openvaet`.`report` (`id`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION);
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_wizard_report_insert` 
BEFORE INSERT ON `wizard_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();
ALTER TABLE `openvaet`.`wizard_report` 
ADD COLUMN `patientAgeConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `creationTimestamp`,
ADD COLUMN `patientAgeConfirmationTimestamp` INT NULL AFTER `patientAgeConfirmationRequired`,
ADD COLUMN `patientAgeConfirmation` BIT(1) NULL AFTER `patientAgeConfirmationTimestamp`;
ALTER TABLE `openvaet`.`wizard_report` 
CHANGE COLUMN `id` `id` INT NOT NULL AUTO_INCREMENT ;

######################### V 10 - 2022-09-19 19:50:00
# Created age_wizard_report table.
CREATE TABLE `age_wizard_report` (
  `id` int NOT NULL AUTO_INCREMENT,
  `reportId` int NOT NULL,
  `creationTimestamp` int NOT NULL,
  `patientAgeConfirmationRequired` bit(1) NOT NULL DEFAULT b'0',
  `patientAgeConfirmationTimestamp` int DEFAULT NULL,
  `patientAgeConfirmation` bit(1) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `age_wizard_report_to_report` (`reportId`),
  CONSTRAINT `age_wizard_report_to_report` FOREIGN KEY (`reportId`) REFERENCES `report` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_age_wizard_report_insert` 
BEFORE INSERT ON `age_wizard_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Created pregnancy_wizard_report table.
CREATE TABLE `pregnancy_wizard_report` (
  `id` int NOT NULL AUTO_INCREMENT,
  `reportId` int NOT NULL,
  `creationTimestamp` int NOT NULL,
  `pregnancyConfirmationRequired` bit(1) NOT NULL DEFAULT b'0',
  `pregnancyConfirmationTimestamp` int DEFAULT NULL,
  `pregnancyConfirmation` bit(1) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `pregnancy_wizard_report_to_report` (`reportId`),
  CONSTRAINT `pregnancy_wizard_report_to_report` FOREIGN KEY (`reportId`) REFERENCES `report` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_pregnancy_wizard_report_insert` 
BEFORE INSERT ON `pregnancy_wizard_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added pregnancy basic data to the reports.
ALTER TABLE `openvaet`.`report` 
ADD COLUMN `hasLikelyPregnancySymptom` BIT(1) NOT NULL DEFAULT 0 AFTER `hoursBetweenVaccineAndAE`,
ADD COLUMN `hasDirectPregnancySymptom` BIT(1) NOT NULL DEFAULT 0 AFTER `hasLikelyPregnancySymptom`,
ADD COLUMN `pregnancyConfirmation` BIT(1) NULL AFTER `hasDirectPregnancySymptom`,
ADD COLUMN `pregnancyConfirmationTimestamp` INT NULL AFTER `pregnancyConfirmation`,
ADD COLUMN `pregnancyConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyConfirmationTimestamp`;
ALTER TABLE `openvaet`.`report` 
ADD COLUMN `pregnancyConfirmationUserId` INT NULL AFTER `pregnancyConfirmationRequired`,
ADD INDEX `report_to_pregnancyConfirmationUser_idx` (`pregnancyConfirmationUserId` ASC);
ALTER TABLE `openvaet`.`report` 
ADD CONSTRAINT `report_to_pregnancyConfirmationUser`
  FOREIGN KEY (`pregnancyConfirmationUserId`)
  REFERENCES `openvaet`.`user` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;

# Dropped obsolete wizard_report table.
DROP TABLE `openvaet`.`wizard_report`;

######################### V 11 - 2022-09-20 04:30:00
# Created breast_milk_wizard_report table.
CREATE TABLE `breast_milk_wizard_report` (
  `id` int NOT NULL AUTO_INCREMENT,
  `reportId` int NOT NULL,
  `creationTimestamp` int NOT NULL,
  `breastMilkExposureConfirmationRequired` bit(1) NOT NULL DEFAULT b'0',
  `breastMilkExposureConfirmationTimestamp` int DEFAULT NULL,
  `breastMilkExposureConfirmation` bit(1) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `breast_milk_wizard_report_to_report` (`reportId`),
  CONSTRAINT `breast_milk_wizard_report_to_report` FOREIGN KEY (`reportId`) REFERENCES `report` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
USE `openvaet`$$
DELIMITER ;
CREATE TRIGGER `before_breast_milk_wizard_report_insert` 
BEFORE INSERT ON `breast_milk_wizard_report` 
FOR EACH ROW  
SET NEW.`creationTimestamp` = UNIX_TIMESTAMP();

# Added breastMilkExposureConfirmaton data to report.
ALTER TABLE `openvaet`.`report` 
ADD COLUMN `breastMilkExposureConfirmationRequired` BIT(1) NOT NULL DEFAULT 0 AFTER `pregnancyConfirmationUserId`,
ADD COLUMN `breastMilkExposureConfirmationTimestamp` INT(11) NULL AFTER `breastMilkExposureConfirmationRequired`,
ADD COLUMN `breastMilkExposureConfirmation` BIT(1) NULL AFTER `breastMilkExposureConfirmationTimestamp`;
ALTER TABLE `openvaet`.`report` 
ADD COLUMN `breastMilkExposureConfirmationUserId` INT NULL AFTER `breastMilkExposureConfirmation`,
ADD INDEX `report_to_breastMilkExposureConfirmationUser_idx` (`breastMilkExposureConfirmationUserId` ASC);
ALTER TABLE `openvaet`.`report` 
ADD CONSTRAINT `report_to_breastMilkExposureConfirmationUser`
  FOREIGN KEY (`breastMilkExposureConfirmationUserId`)
  REFERENCES `openvaet`.`user` (`id`)
  ON DELETE NO ACTION
  ON UPDATE NO ACTION;


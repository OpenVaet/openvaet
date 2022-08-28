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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
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


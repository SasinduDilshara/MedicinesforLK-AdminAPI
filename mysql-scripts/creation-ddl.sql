CREATE TABLE IF NOT EXISTS SUPPLIER (
             SUPPLIERID INT NOT NULL AUTO_INCREMENT,
             NAME VARCHAR (255) NOT NULL,
             SHORTNAME VARCHAR (25) NOT NULL,
             EMAIL VARCHAR (50) NOT NULL,             
             PHONENUMBER VARCHAR (20) NOT NULL,
             PRIMARY KEY (SUPPLIERID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS MEDICALITEM (
             ITEMID INT NOT NULL AUTO_INCREMENT,
             `TYPE` VARCHAR (255) NOT NULL,
             NAME VARCHAR (255) NOT NULL,
             UNIT VARCHAR (50) NOT NULL,
             PRIMARY KEY (ITEMID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS BENEFICIARY (
             BENEFICIARYID INT NOT NULL AUTO_INCREMENT,
             `NAME` VARCHAR (255) NOT NULL,
             SHORTNAME VARCHAR (20) NOT NULL,
             EMAIL VARCHAR (50) NOT NULL,             
             PHONENUMBER VARCHAR (20) NOT NULL,
             PRIMARY KEY (BENEFICIARYID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS DONAR (
             DONARID INT NOT NULL AUTO_INCREMENT,
             ORGNAME VARCHAR (255) NOT NULL,
             ORGLINK VARCHAR (255) NOT NULL,
             EMAIL VARCHAR (50) NOT NULL,             
             PHONENUMBER VARCHAR (20) NOT NULL,
             PRIMARY KEY (DONARID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS MEDICAL_NEED (
             NEEDID INT NOT NULL AUTO_INCREMENT,
             ITEMID VARCHAR (20),
             BENEFICIARYID VARCHAR (20),
             `PERIOD` TIMESTAMP NOT NULL,
             URGENCY VARCHAR (50) NOT NULL,
             PRIMARY KEY (NEEDID),
             FOREIGN KEY (ITEMID) REFERENCES MEDICAL_ITEM(ITEMID),
             CONSTRAINT CHK_NEED_URGENCY CHECK (`URGENCY` IN ('Normal', 'Critical', 'Urgent'))
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS QUOTATION_ITEM (
             QUOTATIONITEMID INT NOT NULL AUTO_INCREMENT,
             SUPPLIERID VARCHAR (20),
             NEEDID VARCHAR (20),
             BRANDNAME VARCHAR (50) NOT NULL,
             AVAILABLEQTY INT NOT NULL DEFAULT 0,
             `EXPIRYDATE` TIMESTAMP NOT NULL,
             UNITPRICE DECIMAL(15, 2) NOT NULL DEFAULT 0,
             PRIMARY KEY (QUOTATIONITEMID),
             FOREIGN KEY (SUPPLIERID) REFERENCES SUPPLIER(SUPPLIERID), 
             FOREIGN KEY (NEEDID) REFERENCES MEDICAL_NEED(NEEDID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS AID_PACKAGE (
             PACKAGEID INT NOT NULL AUTO_INCREMENT,
             NAME VARCHAR (20) NOT NULL,
             `DESCRIPTION` VARCHAR (1500) NOT NULL,
             `STATUS` VARCHAR (20) NOT NULL,
             PRIMARY KEY (PACKAGEID),
             CONSTRAINT CHK_PACKAGE_STATUS CHECK (`STATUS` 
             IN ('Unfunded', 'Partially Funded', 'Fully Funded',
             	 'Awaiting Payment', 'Ordered', 'Shipped',
             	 'Received MoH', 'Delivery InProgess', 'Delivered'))
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS AID_PACKAGE_QUOTATION_MAPPING (
             QUOTATIONITEMID INT NOT NULL AUTO_INCREMENT,
             PACKAGEID VARCHAR (20),
             QTY INT NOT NULL DEFAULT 0,
             PRIMARY KEY (QUOTATIONITEMID, PACKAGEID),
             FOREIGN KEY (QUOTATIONITEMID) REFERENCES QUOTATION_ITEM(QUOTATIONITEMID), 
             FOREIGN KEY (PACKAGEID) REFERENCES AID_PACKAGE(PACKAGEID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS AID_PACKAGAE_UPDATE (
             PACKAGAEUPDATEID INT NOT NULL AUTO_INCREMENT,
             PACKAGEID VARCHAR (20),
             `UPDATE` VARCHAR (1500) NOT NULL,
             `DATE`  TIMESTAMP NOT NULL,
             PRIMARY KEY (PACKAGAEUPDATEID),
             FOREIGN KEY (PACKAGEID) REFERENCES AID_PACKAGE(PACKAGEID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS PLEDGE (
             PLEDGEID INT NOT NULL AUTO_INCREMENT,
             PACKAGEID VARCHAR (20),
             DONAR_ID VARCHAR (20),
             `STATUS` VARCHAR (20) NOT NULL,
             CONSTRAINT CHK_PLEDGE_STATUS CHECK (`STATUS` 
             IN ('Pledged', 'Payment Initiated', 'Payment Confirmed')),
             PRIMARY KEY (PLEDGEID),
             FOREIGN KEY (PACKAGEID) REFERENCES AID_PACKAGE(PACKAGEID),
             FOREIGN KEY (DONARID) REFERENCES DONAR(DONARID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS PLEDGE_UPDATE (
             PLEDGEUPDATEID INT NOT NULL AUTO_INCREMENT,
             PLEDGEID VARCHAR(20),
             `UPDATE` VARCHAR (1500) NOT NULL,
             `DATE`  TIMESTAMP NOT NULL,
             PRIMARY KEY (PLEDGEUPDATEID),
             FOREIGN KEY (PLEDGEID) REFERENCES PLEDGE(PLEDGEID)
)ENGINE INNODB;
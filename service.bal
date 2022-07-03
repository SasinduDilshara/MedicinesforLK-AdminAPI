import ballerina/http;
import ballerinax/mysql;
import ballerina/sql;
import ballerina/time;
import ballerina/io;
import ballerina/uuid;

final mysql:Client dbClient = check new (dbHost, dbUser, dbPass, db, dbPort);

# A service representing a network-accessible API bound to port `9090`.
service /admin on new http:Listener(9090) {

    # A resource for reading all MedicalNeedInfo
    # + return - List of MedicalNeedInfo
    resource function get medicalneeds() returns MedicalNeedInfo[]|error {
        MedicalNeedInfo[] medicalNeedInfo = [];
        stream<MedicalNeedInfo, error?> resultStream = dbClient->query(`SELECT I.NAME, I.ITEMID, NEEDID, PERIOD, URGENCY,
                                                                        NEEDEDQUANTITY, REMAININGQUANTITY
                                                                        FROM MEDICAL_NEED N
                                                                        LEFT JOIN MEDICAL_ITEM I ON I.ITEMID=N.ITEMID;`);
        check from MedicalNeedInfo info in resultStream
            do {
                medicalNeedInfo.push(info);
            };
        check resultStream.close();
        foreach MedicalNeedInfo info in medicalNeedInfo {
            info.period.day = 1;
            info.supplierQuotes = [];
            info.beneficiary = check dbClient->queryRow(`SELECT B.BENEFICIARYID, B.NAME, B.SHORTNAME, B.EMAIL, 
                                                        B.PHONENUMBER 
                                                        FROM BENEFICIARY B RIGHT JOIN MEDICAL_NEED M 
                                                        ON B.BENEFICIARYID=M.BENEFICIARYID
                                                        WHERE M.NEEDID=${info.needID};`);
            stream<Quotation, error?> resultQuotationStream = dbClient->query(`SELECT QUOTATIONID, SUPPLIERID,
                                                                               BRANDNAME, AVAILABLEQUANTITY, PERIOD,
                                                                               EXPIRYDATE, UNITPRICE, REGULATORYINFO
                                                                               FROM QUOTATION Q
                                                                               WHERE YEAR(Q.PERIOD)=${info.period.year} 
                                                                               AND MONTH(Q.PERIOD)=${info.period.month} 
                                                                               AND Q.ITEMID=${info.itemID};`);
            check from Quotation quotation in resultQuotationStream
                do {
                    quotation.supplier = check dbClient->queryRow(`SELECT SUPPLIERID, NAME, SHORTNAME, EMAIL, PHONENUMBER 
                                                               FROM SUPPLIER
                                                               WHERE SUPPLIERID=${quotation.supplierID}`);
                    info.supplierQuotes.push(quotation);
                };
            check resultQuotationStream.close();
        }
        return medicalNeedInfo;
    }

    # A resource for creating Supplier
    # + return - Supplier
    resource function post supplier(@http:Payload Supplier supplier) returns Supplier|error {
        sql:ParameterizedQuery query = `INSERT INTO SUPPLIER(NAME, SHORTNAME, EMAIL, PHONENUMBER)
                                        VALUES (${supplier.name}, ${supplier.shortName},
                                                ${supplier.email}, ${supplier.phoneNumber});`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            supplier.supplierID = lastInsertedID;
        }
        return supplier;
    }

    # A resource for reading all Suppliers
    # + return - List of Suppliers
    resource function get suppliers() returns Supplier[]|error {
        Supplier[] suppliers = [];
        stream<Supplier, error?> resultStream = dbClient->query(`SELECT SUPPLIERID, NAME, SHORTNAME, EMAIL, PHONENUMBER 
                                                                 FROM SUPPLIER`);
        check from Supplier supplier in resultStream
            do {
                suppliers.push(supplier);
            };
        check resultStream.close();
        return suppliers;
    }

    # A resource for fetching a Supplier
    # + return - A Supplier
    resource function get suppliers/[int supplierId]() returns Supplier|error {
        Supplier supplier = check dbClient->queryRow(`SELECT SUPPLIERID, NAME, SHORTNAME, EMAIL, PHONENUMBER FROM SUPPLIER
                                                      WHERE SUPPLIERID=${supplierId}`);
        return supplier;
    }

    # A resource for creating Quotation
    # + return - Quotation
    resource function post quotation(@http:Payload Quotation quotation) returns Quotation|error {
        quotation.period.day = 1;
        sql:ParameterizedQuery query = `INSERT INTO QUOTATION(SUPPLIERID, ITEMID, BRANDNAME, AVAILABLEQUANTITY, PERIOD,
                                        EXPIRYDATE, UNITPRICE, REGULATORYINFO)
                                        VALUES (${quotation.supplierID}, ${quotation.itemID}, ${quotation.brandName},
                                                ${quotation.availableQuantity}, ${quotation.period},
                                                ${quotation.expiryDate}, ${quotation.unitPrice}, ${quotation.regulatoryInfo});`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            quotation.quotationID = lastInsertedID;
        }
        quotation.supplier = check dbClient->queryRow(`SELECT SUPPLIERID, NAME, SHORTNAME, EMAIL, PHONENUMBER FROM SUPPLIER
                                                       WHERE SUPPLIERID=${quotation.supplierID}`);
        return quotation;
    }

    # A resource for reading all Aid-Packages
    # + return - List of Aid-Packages and optionally filter by status
    resource function get aidpackages(string? status) returns AidPackage[]|error {
        AidPackage[] aidPackages = [];
        stream<AidPackage, error?> resultStream = dbClient->query(`SELECT PACKAGEID, NAME, DESCRIPTION, STATUS 
                                                                    FROM AID_PACKAGE
                                                                    WHERE ${status} IS NULL OR STATUS=${status};`);
        check from AidPackage aidPackage in resultStream
            do {
                aidPackages.push(aidPackage);
            };
        check resultStream.close();
        foreach AidPackage aidPackage in aidPackages {
            aidPackage.aidPackageItems = [];
            stream<AidPackageItem, error?> resultItemStream = dbClient->query(`SELECT PACKAGEITEMID, PACKAGEID, QUOTATIONID,
                                                                               NEEDID, QUANTITY, TOTALAMOUNT 
                                                                               FROM AID_PACKAGE_ITEM
                                                                               WHERE PACKAGEID=${aidPackage.packageID};`);
            check from AidPackageItem aidPackageItem in resultItemStream
                do {
                    aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                                        QUOTATIONID, SUPPLIERID, BRANDNAME,
                                                                        AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                                        UNITPRICE, REGULATORYINFO
                                                                        FROM QUOTATION 
                                                                        WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
                    aidPackage.aidPackageItems.push(aidPackageItem);
                };
            check resultItemStream.close();
        }
        return aidPackages;
    }

    # A resource for fetching an Aid-Package
    # + return - Aid-Package
    resource function get aidpackages/[int packageID]() returns AidPackage|error {
        AidPackage aidPackage = check dbClient->queryRow(`SELECT PACKAGEID, NAME, DESCRIPTION, STATUS FROM AID_PACKAGE
                                                          WHERE PACKAGEID=${packageID};`);
        stream<AidPackageItem, error?> resultItemStream = dbClient->query(`SELECT PACKAGEITEMID, PACKAGEID, QUOTATIONID,
                                                                           NEEDID, QUANTITY, TOTALAMOUNT 
                                                                           FROM AID_PACKAGE_ITEM
                                                                           WHERE PACKAGEID=${packageID};`);
        aidPackage.aidPackageItems = [];
        check from AidPackageItem aidPackageItem in resultItemStream
            do {
                aidPackage.aidPackageItems.push(aidPackageItem);
            };
        check resultItemStream.close();
        foreach AidPackageItem? aidPackageItem in aidPackage.aidPackageItems {
            if aidPackageItem is AidPackageItem {
                aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                                    QUOTATIONID, SUPPLIERID, BRANDNAME,
                                                                    AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                                    UNITPRICE, REGULATORYINFO
                                                                    FROM QUOTATION 
                                                                    WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
            }
        }
        return aidPackage;
    }

    # A resource for creating Aid-Package
    # + return - Aid-Package
    resource function post aidpackages(@http:Payload AidPackage aidPackage) returns AidPackage|error {
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGE(NAME, DESCRIPTION, STATUS)
                                        VALUES (${aidPackage.name}, ${aidPackage.description}, ${aidPackage.status});`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackage.packageID = lastInsertedID;
        }
        return aidPackage;
    }

    # A resource for modifying Aid-Package
    # + return - Aid-Package
    resource function patch aidpackages(@http:Payload AidPackage aidPackage) returns AidPackage|error {
        sql:ParameterizedQuery query = `UPDATE AID_PACKAGE
                                        SET
                                        NAME=COALESCE(${aidPackage.name},NAME), 
                                        DESCRIPTION=COALESCE(${aidPackage.description},DESCRIPTION),
                                        STATUS=COALESCE(${aidPackage.status},STATUS)
                                        WHERE PACKAGEID=${aidPackage.packageID};`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackage.packageID = lastInsertedID;
        }
        stream<AidPackageItem, error?> resultItemStream = dbClient->query(`SELECT PACKAGEITEMID, PACKAGEID, QUOTATIONID,
                                                                           NEEDID, QUANTITY, TOTALAMOUNT 
                                                                           FROM AID_PACKAGE_ITEM
                                                                           WHERE PACKAGEID=${aidPackage.packageID};`);
        aidPackage.aidPackageItems = [];
        check from AidPackageItem aidPackageItem in resultItemStream
            do {
                aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                                    QUOTATIONID, SUPPLIERID, BRANDNAME,
                                                                    AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                                    UNITPRICE, REGULATORYINFO
                                                                    FROM QUOTATION 
                                                                    WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
                aidPackage.aidPackageItems.push(aidPackageItem);
            };
        check resultItemStream.close();
        return aidPackage;
    }

    # A resource for creating AidPackage-Item
    # + return - AidPackage-Item
    resource function post aidPackages/[int packageID]/aidpackageitems(@http:Payload AidPackageItem aidPackageItem)
                                                                    returns AidPackageItem|error {
        aidPackageItem.packageID = packageID;
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGE_ITEM(QUOTATIONID, PACKAGEID, NEEDID, QUANTITY)
                                        VALUES (${aidPackageItem.quotationID}, ${aidPackageItem.packageID},
                                                ${aidPackageItem.needID}, ${aidPackageItem.quantity});`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackageItem.packageItemID = lastInsertedID;
        }
        query = `UPDATE MEDICAL_NEED
                 SET REMAININGQUANTITY=NEEDEDQUANTITY-(SELECT SUM(QUANTITY) FROM 
                     AID_PACKAGE_ITEM WHERE NEEDID=${aidPackageItem.needID})
                 WHERE NEEDID=${aidPackageItem.needID};`;
        _ = check dbClient->execute(query);
        aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                            QUOTATIONID, SUPPLIERID, BRANDNAME,
                                                            AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                            UNITPRICE, REGULATORYINFO
                                                            FROM QUOTATION 
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
        return aidPackageItem;
    }

    # A resource for updating AidPackage-Item
    # + return - AidPackage-Item
    resource function put aidpackages/[int packageID]/aidpackageitems(@http:Payload AidPackageItem aidPackageItem)
                                                                    returns AidPackageItem|error {
        aidPackageItem.packageID = packageID;
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGE_ITEM(QUOTATIONID, PACKAGEID, NEEDID, QUANTITY)
                                        VALUES (${aidPackageItem.quotationID}, ${aidPackageItem.packageID},
                                                ${aidPackageItem.needID}, ${aidPackageItem.quantity})
                                        ON DUPLICATE KEY UPDATE 
                                        QUANTITY=COALESCE(${aidPackageItem.quantity}, QUANTITY);`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackageItem.packageItemID = lastInsertedID;
        }
        query = `UPDATE MEDICAL_NEED
                 SET REMAININGQUANTITY=NEEDEDQUANTITY-(SELECT SUM(QUANTITY) FROM 
                     AID_PACKAGE_ITEM WHERE NEEDID=${aidPackageItem.needID})
                 WHERE NEEDID=${aidPackageItem.needID};`;
        _ = check dbClient->execute(query);
        aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                            QUOTATIONID, SUPPLIERID, BRANDNAME,
                                                            AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                            UNITPRICE, REGULATORYINFO
                                                            FROM QUOTATION 
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
        return aidPackageItem;
    }

    # A resource for removing an AidPackage-Item
    # + return - aidPackageItem
    resource function delete aidpackageitems/[int packageItemID] () returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM AID_PACKAGAE_ITEM 
                                        WHERE PACKAGEITEMID=${packageItemID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return packageItemID;
    }

    # A resource for fetching all comments of an Aid-Package
    # + return - list of AidPackageUpdateComments
    resource function get aidPackages/[int packageID]/updatecomments() returns AidPackageUpdate[]|error {
        AidPackageUpdate[] aidPackageUpdates = [];
        stream<AidPackageUpdate, error?> resultStream = dbClient->query(`SELECT
                                                                         PACKAGEID, PACKAGEUPDATEID, UPDATECOMMENT, DATETIME 
                                                                         FROM AID_PACKAGAE_UPDATE
                                                                         WHERE PACKAGEID=${packageID};`);
        check from AidPackageUpdate aidPackageUpdate in resultStream
            do {
                aidPackageUpdates.push(aidPackageUpdate);
            };
        check resultStream.close();
        return aidPackageUpdates;
    }

    # A resource for saving update with a comment to an Aid-Package
    # + return - AidPackageUpdateComment
    resource function put aidPackages/[int packageID]/updatecomments(@http:Payload AidPackageUpdate aidPackageUpdate)
                                                                returns AidPackageUpdate?|error {
        aidPackageUpdate.packageID = packageID;
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGAE_UPDATE(PACKAGEID, PACKAGEUPDATEID, UPDATECOMMENT, DATETIME)
                                        VALUES (${aidPackageUpdate.packageID},
                                                IFNULL(${aidPackageUpdate.packageUpdateId}, DEFAULT(PACKAGEUPDATEID)),
                                                ${aidPackageUpdate.updateComment},
                                                FROM_UNIXTIME(${time:utcNow()[0]})
                                        ) ON DUPLICATE KEY UPDATE
                                        DATETIME=FROM_UNIXTIME(COALESCE(${time:utcNow()[0]}, DATETIME)),
                                        UPDATECOMMENT=COALESCE(${aidPackageUpdate.updateComment}, UPDATECOMMENT);`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackageUpdate.packageUpdateId = lastInsertedID;
        }
        aidPackageUpdate.dateTime = check dbClient->queryRow(`SELECT DATETIME 
                                                              FROM AID_PACKAGAE_UPDATE
                                                              WHERE PACKAGEUPDATEID=${aidPackageUpdate.packageUpdateId};`);
        return aidPackageUpdate;
    }

    # A resource for removing an update comment from an Aid-Package
    # + return - aidPackageUpdateId
    resource function delete aidPackages/[int packageID]/updatecomment/[int packageUpdateID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM AID_PACKAGAE_UPDATE 
                                        WHERE 
                                        PACKAGEID=${packageID} AND
                                        PACKAGEUPDATEID=${packageUpdateID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return packageUpdateID;
    }

    # A resource for fetching all pledges of an Aid-Package
    # + return - list of pledges
    resource function get aidPackage/[int packageID]/pledges() returns Pledge[]|error {
        Pledge[] pledges = [];
        stream<Pledge, error?> resultStream = dbClient->query(`SELECT
                                                               PLEDGEID, PACKAGEID, DONORID, AMOUNT, STATUS 
                                                               FROM PLEDGE
                                                               WHERE PACKAGEID=${packageID};`);
        check from Pledge pledge in resultStream
            do {
                pledge.donor = check dbClient->queryRow(`SELECT
                                                         DONORID, ORGNAME, ORGLINK,
                                                         EMAIL, PHONENUMBER
                                                         FROM DONOR 
                                                         WHERE DONORID=${pledge.donorID}`);
                pledges.push(pledge);
            };
        check resultStream.close();
        return pledges;
    }

    # A resource for fetching all comments of a pledge
    # + return - list of PledgeUpdateComments
    resource function get pledges/[int pledgeID]/updatecomments() returns PledgeUpdate[]|error {
        PledgeUpdate[] PledgeUpdates = [];
        stream<PledgeUpdate, error?> resultStream = dbClient->query(`SELECT
                                                                     PLEDGEID, PLEDGEUPDATEID, UPDATECOMMENT, DATETIME 
                                                                     FROM PLEDGE_UPDATE
                                                                     WHERE PLEDGEID=${pledgeID};`);
        check from PledgeUpdate PledgeUpdate in resultStream
            do {
                PledgeUpdates.push(PledgeUpdate);
            };
        check resultStream.close();
        return PledgeUpdates;
    }

    # A resource for removing a Pldege
    # + return - pledgeID
    resource function delete pledges/[int pledgeID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM PLEDGE 
                                        WHERE
                                        PLEDGEID=${pledgeID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return pledgeID;
    }

    # A resource for saving update with a comment to a Pledge
    # + return - PledgeUpdateComment
    resource function put pledges/[int pledgeID]/updatecomment(@http:Payload PledgeUpdate pledgeUpdate)
                                                                returns PledgeUpdate?|error {
        pledgeUpdate.pledgeID = pledgeID;
        sql:ParameterizedQuery query = `INSERT INTO PLEDGE_UPDATE(PLEDGEID, PLEDGEUPDATEID, UPDATECOMMENT, DATETIME)
                                        VALUES (${pledgeUpdate.pledgeID},
                                                IFNULL(${pledgeUpdate.pledgeUpdateID}, DEFAULT(PLEDGEUPDATEID)),
                                                ${pledgeUpdate.updateComment},
                                                FROM_UNIXTIME(${time:utcNow()[0]})
                                        ) ON DUPLICATE KEY UPDATE
                                        DATETIME=FROM_UNIXTIME(COALESCE(${time:utcNow()[0]}, DATETIME)),
                                        UPDATECOMMENT=COALESCE(${pledgeUpdate.updateComment}, UPDATECOMMENT);`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            pledgeUpdate.pledgeUpdateID = lastInsertedID;
        }
        pledgeUpdate.dateTime = check dbClient->queryRow(`SELECT DATETIME 
                                                          FROM PLEDGE_UPDATE
                                                          WHERE PLEDGEUPDATEID=${pledgeUpdate.pledgeUpdateID};`);
        return pledgeUpdate;
    }

    # A resource for removing an update comment from a Pldege
    # + return - pledgeUpdateID
    resource function delete pledges/[int pledgeID]/updatecomment/[int pledgeUpdateID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM PLEDGE_UPDATE 
                                        WHERE
                                        PLEDGEID=${pledgeID} 
                                        AND PLEDGEUPDATEID=${pledgeUpdateID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return pledgeUpdateID;
    }

    resource function post requirements(http:Caller caller,http:Request request) returns error? {
        stream<byte[], io:Error?> incomingStreamer = check request.getByteStream();
        string uuid = uuid:createType1AsString();
        string filePath="./files/"+uuid+".csv";
        check io:fileWriteBlocksFromStream(filePath, incomingStreamer);
        check incomingStreamer.close();

        string[][] readCsv = check io:fileReadCsv(filePath);
        io:println(readCsv);

        check caller->respond("CSV File Received!");
    }
}
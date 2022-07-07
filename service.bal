import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/mime;
import ballerina/regex;
import ballerina/sql;
import ballerina/time;
import ballerinax/mysql;

final mysql:Client dbClient = check new (dbHost, dbUser, dbPass, db, dbPort);

# A service representing a network-accessible API bound to port `9090`.
service /admin on new http:Listener(9090) {

    # A resource for reading all MedicalNeed
    # + return - List of MedicalNeed
    resource function get medicalneeds() returns MedicalNeed[]|error {
        MedicalNeed[] medicalNeed = [];
        stream<MedicalNeed, error?> resultStream = dbClient->query(`SELECT I.ITEMID, NEEDID, PERIOD, URGENCY,
                                                                        NEEDEDQUANTITY, REMAININGQUANTITY
                                                                        FROM MEDICAL_NEED N
                                                                        LEFT JOIN MEDICAL_ITEM I ON I.ITEMID=N.ITEMID;`);
        check from MedicalNeed info in resultStream
            do {
                info.period.day = 1;
                info.supplierQuotes = [];
                info.beneficiary = check dbClient->queryRow(`SELECT B.BENEFICIARYID, B.NAME, B.SHORTNAME, B.EMAIL, 
                                                        B.PHONENUMBER 
                                                        FROM BENEFICIARY B RIGHT JOIN MEDICAL_NEED M 
                                                        ON B.BENEFICIARYID=M.BENEFICIARYID
                                                        WHERE M.NEEDID=${info.needID};`);
                info.medicalItem = check dbClient->queryRow(`SELECT ITEMID, NAME, TYPE, UNIT 
                                                         FROM MEDICAL_ITEM
                                                         WHERE ITEMID=${info.itemID}`);
                medicalNeed.push(info);
            };
        check resultStream.close();
        foreach MedicalNeed info in medicalNeed {
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
        return medicalNeed;
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
            check constructAidPackageData(aidPackage);
        }
        return aidPackages;
    }

    # A resource for fetching an Aid-Package
    # + return - Aid-Package
    resource function get aidpackages/[int packageID]() returns AidPackage|error {
        AidPackage aidPackage = check dbClient->queryRow(`SELECT PACKAGEID, NAME, DESCRIPTION, STATUS FROM AID_PACKAGE
                                                          WHERE PACKAGEID=${packageID};`);
        check constructAidPackageData(aidPackage);
        return aidPackage;
    }

    # A resource for creating Aid-Package
    # + return - Aid-Package
    resource function post aidpackages(@http:Payload AidPackage aidPackage) returns AidPackage|error {
        sql:ExecutionResult result = check dbClient->execute(`INSERT INTO AID_PACKAGE(NAME, DESCRIPTION, STATUS)
                                        VALUES (${aidPackage.name}, ${aidPackage.description}, ${aidPackage.status});`);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackage.packageID = lastInsertedID;
        }

        foreach AidPackageItem aidPackageItem in aidPackage.aidPackageItems {
            aidPackageItem.packageID = aidPackage.packageID;
            check addAidPackageItemData(aidPackageItem);
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
                                                                QUOTATIONID, SUPPLIERID, ITEMID, BRANDNAME,
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
    resource function post aidpackages/[int packageID]/aidpackageitems(@http:Payload AidPackageItem aidPackageItem)
                                                                    returns AidPackageItem|error {

        Quotation quotation = check dbClient->queryRow(`SELECT
                                                            QUOTATIONID, SUPPLIERID, ITEMID, BRANDNAME,
                                                            AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                            UNITPRICE, REGULATORYINFO
                                                            FROM QUOTATION 
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
        aidPackageItem.packageID = packageID;
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGE_ITEM(QUOTATIONID, PACKAGEID, NEEDID, QUANTITY,TOTALAMOUNT)
                                        VALUES (${aidPackageItem.quotationID}, ${aidPackageItem.packageID},
                                                ${aidPackageItem.needID}, ${aidPackageItem.quantity}, ${<decimal>aidPackageItem.quantity * quotation.unitPrice});`;
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
        aidPackageItem.quotation = quotation;
        return aidPackageItem;
    }

    # A resource for updating AidPackage-Item
    # + return - AidPackage-Item
    resource function put aidpackages/[int packageID]/aidpackageitems(@http:Payload AidPackageItem aidPackageItem)
                                                                    returns AidPackageItem|error {
        if (packageID != aidPackageItem.packageID) {
            return error("Mismatching package ID in request path and AidPackageItem body");
        }
        aidPackageItem.packageID = packageID;

        int|error aidPackageItemID = dbClient->queryRow(`SELECT PACKAGEITEMID 
                                                            FROM AID_PACKAGE_ITEM  
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}
                                                            AND NEEDID = ${aidPackageItem.needID}
                                                            AND PACKAGEID = ${aidPackageItem.packageID}`);
        if (aidPackageItemID is int) {
            _ = check dbClient->execute(`UPDATE AID_PACKAGE_ITEM 
                 SET QUANTITY=${aidPackageItem.quantity} 
                 WHERE PACKAGEITEMID=${aidPackageItemID};`);
        } else {
            sql:ExecutionResult|error result = dbClient->execute(`INSERT INTO AID_PACKAGE_ITEM(QUOTATIONID, PACKAGEID, 
                                        NEEDID, QUANTITY)
                                        VALUES (${aidPackageItem.quotationID}, ${aidPackageItem.packageID},
                                                ${aidPackageItem.needID}, ${aidPackageItem.quantity});`);
            if (result is error) {
                return error(string `Inserting new AID Package item failed due to constraint violation`);
            }
            var lastInsertedID = result.lastInsertId;
            if lastInsertedID is int {
                aidPackageItem.packageItemID = lastInsertedID;
            }
        }

        _ = check dbClient->execute(`UPDATE MEDICAL_NEED
                 SET REMAININGQUANTITY=NEEDEDQUANTITY-(SELECT SUM(QUANTITY) FROM 
                     AID_PACKAGE_ITEM WHERE NEEDID=${aidPackageItem.needID})
                 WHERE NEEDID=${aidPackageItem.needID};`);
        aidPackageItem.quotation = check dbClient->queryRow(`SELECT
                                                            QUOTATIONID, SUPPLIERID, ITEMID, BRANDNAME,
                                                            AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                            UNITPRICE, REGULATORYINFO
                                                            FROM QUOTATION 
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
        return aidPackageItem;
    }

    # A resource for removing an AidPackage-Item
    # + return - aidPackageItem
    resource function delete aidpackages/[int packageID]/aidpackageitems/[int packageItemID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM AID_PACKAGE_ITEM 
                                        WHERE PACKAGEID=${packageID}
                                        AND PACKAGEITEMID=${packageItemID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return packageItemID;
    }

    # A resource for fetching all comments of an Aid-Package
    # + return - list of AidPackageUpdateComments
    resource function get aidpackages/[int packageID]/updatecomments() returns AidPackageUpdate[]|error {
        AidPackageUpdate[] aidPackageUpdates = [];
        stream<AidPackageUpdate, error?> resultStream = dbClient->query(`SELECT
                                                                         PACKAGEID, PACKAGEUPDATEID, UPDATECOMMENT, DATETIME 
                                                                         FROM AID_PACKAGE_UPDATE
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
    resource function put aidpackages/[int packageID]/updatecomments(@http:Payload AidPackageUpdate aidPackageUpdate)
                                                                returns AidPackageUpdate?|error {
        aidPackageUpdate.packageID = packageID;
        sql:ParameterizedQuery query = `INSERT INTO AID_PACKAGE_UPDATE(PACKAGEID, PACKAGEUPDATEID, UPDATECOMMENT, DATETIME)
                                        VALUES (${aidPackageUpdate.packageID},
                                                IFNULL(${aidPackageUpdate.packageUpdateID}, DEFAULT(PACKAGEUPDATEID)),
                                                ${aidPackageUpdate.updateComment},
                                                FROM_UNIXTIME(${time:utcNow()[0]})
                                        ) ON DUPLICATE KEY UPDATE
                                        DATETIME=FROM_UNIXTIME(COALESCE(${time:utcNow()[0]}, DATETIME)),
                                        UPDATECOMMENT=COALESCE(${aidPackageUpdate.updateComment}, UPDATECOMMENT);`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            aidPackageUpdate.packageUpdateID = lastInsertedID;
        }
        aidPackageUpdate.dateTime = check dbClient->queryRow(`SELECT DATETIME 
                                                              FROM AID_PACKAGE_UPDATE
                                                              WHERE PACKAGEUPDATEID=${aidPackageUpdate.packageUpdateID};`);
        return aidPackageUpdate;
    }

    # A resource for removing an update comment from an Aid-Package
    # + return - aidPackageUpdateId
    resource function delete aidpackages/[int packageID]/updatecomment/[int packageUpdateID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM AID_PACKAGE_UPDATE 
                                        WHERE 
                                        PACKAGEID=${packageID} AND
                                        PACKAGEUPDATEID=${packageUpdateID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return packageUpdateID;
    }

    # A resource for fetching all pledges of an Aid-Package
    # + return - list of pledges
    resource function get aidpackage/[int packageID]/pledges() returns Pledge[]|error {
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

    # A resource for fetching details of all pledges
    # + return - list of Pledges
    resource function get pledges() returns Pledge[]|error {
        Pledge[] pledges = [];
        stream<Pledge, error?> resultStream = dbClient->query(`SELECT PLEDGEID, PACKAGEID, DONORID, AMOUNT, STATUS 
                                                                     FROM PLEDGE;`);
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

    # A resource for fetching pledge for a given pledge ID
    # + return - Pledge
    resource function get pledges/[int pledgeID]() returns Pledge|error {
        Pledge pledge = check dbClient->queryRow(`SELECT PLEDGEID, PACKAGEID, DONORID, AMOUNT, STATUS 
                                                                     FROM PLEDGE WHERE PLEDGEID=${pledgeID};`);
        pledge.donor = check dbClient->queryRow(`SELECT
                                                        DONORID, ORGNAME, ORGLINK,
                                                        EMAIL, PHONENUMBER
                                                        FROM DONOR 
                                                        WHERE DONORID=${pledge.donorID}`);
        return pledge;
    }

    # A resource for fetching all comments of a pledge
    # + return - list of PledgeUpdateComments
    resource function get pledges/[int pledgeID]/updatecomments() returns PledgeUpdate[]|error {
        PledgeUpdate[] pledgeUpdates = [];
        stream<PledgeUpdate, error?> resultStream = dbClient->query(`SELECT
                                                                     PLEDGEID, PLEDGEUPDATEID, UPDATECOMMENT, DATETIME 
                                                                     FROM PLEDGE_UPDATE
                                                                     WHERE PLEDGEID=${pledgeID};`);
        check from PledgeUpdate pledgeUpdate in resultStream
            do {
                pledgeUpdates.push(pledgeUpdate);
            };
        check resultStream.close();
        return pledgeUpdates;
    }

    # A resource for removing a Pldege
    # + return - pledgeID
    resource function delete pledges/[int pledgeID]() returns int|error
    {
        sql:ParameterizedQuery query = `DELETE FROM PLEDGE_UPDATE 
                                        WHERE
                                        PLEDGEID=${pledgeID}`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        query = `DELETE FROM PLEDGE 
                 WHERE
                 PLEDGEID=${pledgeID};`;
        sql:ExecutionResult _ = check dbClient->execute(query);
        return pledgeID;
    }

    # A resource for saving update with a comment to a Pledge
    # + return - PledgeUpdateComment
    resource function put pledges/[int pledgeID]/updatecomment(@http:Payload PledgeUpdate pledgeUpdate) returns PledgeUpdate?|error {
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
        _ = check dbClient->execute(query);
        return pledgeUpdateID;
    }

    # A resource for update status of a Pldege
    # + return - pledgeUpdateID
    resource function patch pledges/[int pledgeID]/status/[string status]() returns Pledge|error
    {
        _ = check dbClient->execute(`UPDATE PLEDGE 
                                        SET STATUS = ${status}
                                        WHERE PLEDGEID=${pledgeID};`);
        Pledge pledge = check dbClient->queryRow(`SELECT PLEDGEID, PACKAGEID, DONORID, AMOUNT, STATUS 
                                                                     FROM PLEDGE WHERE PLEDGEID=${pledgeID};`);
        return pledge;
    }

    # A resource for uploading medical needs CSV file
    #
    # + request - http:Request with the file payload
    # + return - Return http:Response or an error
    resource function post requirements/medicalneeds(http:Request request) returns http:Response|error {
        http:Response response = new;
        string[][] csvLines = check handleCSVBodyParts(request);
        MedicalNeed[] medicalNeeds = check createMedicalNeedsFromCSVData(csvLines);
        error? ret = updateMedicalNeedsTable(medicalNeeds);
        if ret is error {
            return ret;
        } else {
            response.setPayload("CSV File uploaded successfully");
            return response;
        }
    }

    # Resource for uploading quotations
    #
    # + request - http:Request with the file payload
    # + return - Return http:Response or an error
    resource function post quotations(http:Request request) returns http:Response|error {
        http:Response response = new;

        string[][] csvLines = check handleCSVBodyParts(request);
        Quotation[] quotations = check createQuotationFromCSVData(csvLines);
        error? ret = updateQuotationsTable(quotations);
        if ret is error {
            return ret;
        } else {
            response.setPayload("CSV File uploaded successfully");
            return response;
        }
    }

    # A resource for creating Donor
    # + return - Donor
    resource function post donor(@http:Payload Donor donor) returns Donor|error {
        sql:ParameterizedQuery query = `INSERT INTO DONOR(ORGNAME, ORGLINK, EMAIL, PHONENUMBER)
                                        VALUES (${donor.orgName}, ${donor.orgLink}, ${donor.email},${donor.phoneNumber});`;
        sql:ExecutionResult result = check dbClient->execute(query);
        var lastInsertedID = result.lastInsertId;
        if lastInsertedID is int {
            donor.donorID = lastInsertedID;
        }
        return donor;
    }
}

function constructAidPackageData(AidPackage aidPackage) returns error? {
    aidPackage.aidPackageItems = [];
    stream<AidPackageItem, error?> resultItemStream = dbClient->query(`SELECT PACKAGEITEMID, PACKAGEID, QUOTATIONID,
                                                                               NEEDID, QUANTITY, TOTALAMOUNT 
                                                                               FROM AID_PACKAGE_ITEM
                                                                               WHERE PACKAGEID=${aidPackage.packageID};`);
    decimal totalAmount = 0;
    check from AidPackageItem aidPackageItem in resultItemStream
        do {
            Quotation quotation = check dbClient->queryRow(`SELECT
                                                                    QUOTATIONID, SUPPLIERID, ITEMID, BRANDNAME,
                                                                    AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                                    UNITPRICE, REGULATORYINFO
                                                                    FROM QUOTATION 
                                                                    WHERE QUOTATIONID=${aidPackageItem.quotationID}`); //TODO:What if row is not there
            quotation.supplier = check dbClient->queryRow(`SELECT
                                                                    SUPPLIERID, NAME, SHORTNAME,
                                                                    EMAIL, PHONENUMBER 
                                                                    FROM SUPPLIER 
                                                                    WHERE SUPPLIERID=${quotation.supplierID}`);
            aidPackageItem.quotation = quotation;
            aidPackage.aidPackageItems.push(aidPackageItem);
            totalAmount = totalAmount + aidPackageItem.totalAmount;
        };
    check resultItemStream.close();
    aidPackage.goalAmount = totalAmount;
    decimal|error recievedAmount = dbClient->queryRow(`SELECT IFNULL(SUM(AMOUNT),0) FROM PLEDGE 
                                                        WHERE PACKAGEID = ${aidPackage.packageID};`);
    if (recievedAmount is decimal) {
        aidPackage.receivedAmount = recievedAmount;
    }
}

function addAidPackageItemData(AidPackageItem aidPackageItem) returns error? {
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
                                                            QUOTATIONID, SUPPLIERID, ITEMID, BRANDNAME,
                                                            AVAILABLEQUANTITY, PERIOD, EXPIRYDATE,
                                                            UNITPRICE, REGULATORYINFO
                                                            FROM QUOTATION 
                                                            WHERE QUOTATIONID=${aidPackageItem.quotationID}`);
}

function handleCSVBodyParts(http:Request request) returns string[][]|error {
    var bodyParts = request.getBodyParts();
    if (bodyParts is mime:Entity[]) {
        string[][] csvLines = [];
        foreach var bodyPart in bodyParts {
            var mediaType = mime:getMediaType(bodyPart.getContentType());
            if (mediaType is mime:MediaType) {
                string baseType = mediaType.getBaseType();
                if ("text/csv" == baseType) {
                    byte[] payload = check bodyPart.getByteArray();
                    csvLines = check getCSVData(payload);
                } else {
                    return error("Invalid base type, not text/csv");
                }
            } else {
                return error("Invalid media type");
            }
        }
        return csvLines;
    } else {
        return error("Error in decoding multiparts!");
    }
}

function getCSVData(byte[] payload) returns string[][]|error {
    io:ReadableByteChannel readableByteChannel = check io:createReadableChannel(payload);
    io:ReadableCharacterChannel readableCharacterChannel = new (readableByteChannel, "UTF-8");
    io:ReadableCSVChannel readableCSVChannel = new io:ReadableCSVChannel(readableCharacterChannel, ",", 1);
    return check channelReadCsv(readableCSVChannel);
}

function channelReadCsv(io:ReadableCSVChannel readableCSVChannel) returns string[][]|error {
    string[][] results = [];
    int i = 0;
    while readableCSVChannel.hasNext() {
        var records = readableCSVChannel.getNext();
        if records is string[] {
            results[i] = records;
            i += 1;
        } else if records is error {
            check readableCSVChannel.close();
            return records;
        }
    }
    check readableCSVChannel.close();
    return results;
}

function readMedicalNeedsCSVLine(string[] line, int csvLineNo) returns [string, int, string, string, string, string, string, int]|error => [
    line[0],
    check readIntCSVField(line[1], csvLineNo),
    line[2],
    line[3],
    line[4],
    line[5],
    line[6],
    check readIntCSVField(line[7], csvLineNo)
];

function readSupplyQuotationsCSVLine(string[] line, int csvLineNo) returns [string, string, string, string, string, string, int, string, decimal]|error => [
    line[0],
    line[1],
    line[2],
    line[3],
    line[4],
    line[5],
    check readIntCSVField(line[6], csvLineNo),
    line[7],
    check readDollerCSVField(line[8], csvLineNo)
];

function readIntCSVField(string value, int csvLineNo) returns int|error {
    int|error intVal = int:fromString(value.trim());
    if (intVal is error) {
        return error(string `Error in parsing int:${value} in line ${csvLineNo}`);
    }
    return intVal;
}

function readDollerCSVField(string value, int csvLineNo) returns decimal|error {
    decimal|error decimalVal = decimal:fromString(value.substring(1, value.length() - 1).trim());
    if (decimalVal is error) {
        return error(string `Error in parsing doller amount:${value} in line ${csvLineNo}`);
    }
    return decimalVal;
}

function createMedicalNeedsFromCSVData(string[][] inputCSVData) returns MedicalNeed[]|error {
    MedicalNeed[] medicalNeeds = [];
    string errorMessages = "";
    int csvLineNo = 0;
    foreach var line in inputCSVData {
        boolean hasError = false;
        int medicalItemId = -1;
        int medicalBeneficiaryId = -1;
        csvLineNo += 1;
        if (line.length() == 8) {
            var [_, _, urgency, period, beneficiary, itemName, _, neededQuantity] = check readMedicalNeedsCSVLine(line, csvLineNo);
            int|error itemID = dbClient->queryRow(`SELECT ITEMID FROM MEDICAL_ITEM WHERE NAME=${itemName};`);
            if (itemID is error) {
                errorMessages = errorMessages + string `Line:${csvLineNo}| ${itemName} is missing in MEDICAL_ITEM table 
`;
                hasError = true;
            } else {
                medicalItemId = itemID;
            }
            int|error beneficiaryID = dbClient->queryRow(`SELECT BENEFICIARYID FROM BENEFICIARY WHERE NAME=${beneficiary};`);
            if (beneficiaryID is error) {
                errorMessages = errorMessages + string `Line:${csvLineNo}| ${beneficiary} is missing in BENEFICIARY table 
`;
                hasError = true;
            } else {
                medicalBeneficiaryId = beneficiaryID;
            }

            if (!hasError) {
                MedicalNeed medicalNeed = {
                    itemID: medicalItemId,
                    beneficiaryID: medicalBeneficiaryId,
                    period: check getPeriod(period),
                    urgency,
                    neededQuantity
                };
                medicalNeeds.push(medicalNeed);
            }
        }
        else {
            log:printError(string `Invalid CSV Length in line:${csvLineNo}`);
        }
    }
    if (errorMessages.length() > 0) {
        return error(errorMessages);
    }
    return medicalNeeds;
}

function createQuotationFromCSVData(string[][] inputCSVData) returns Quotation[]|error {
    Quotation[] qutoations = [];
    string errorMessages = "";
    int csvLineNo = 0;
    foreach var line in inputCSVData {
        boolean hasError = false;
        int medicalItemId = -1;
        int quotationSupplierId = -1;
        csvLineNo += 1;
        if (line.length() == 9) {
            var [_, supplier, itemNeeded, regulatoryInfo, brandName, period, availableQuantity, expiryDate, unitPrice]
                = check readSupplyQuotationsCSVLine(line, csvLineNo);
            int|error itemID = dbClient->queryRow(`SELECT ITEMID FROM MEDICAL_ITEM WHERE NAME=${itemNeeded};`);
            if (itemID is error) {
                errorMessages = errorMessages + string `Line:${csvLineNo}| ${itemNeeded} is missing in MEDICAL_ITEM table
`;
                hasError = true;
            } else {
                medicalItemId = itemID;
            }
            int|error supplierID = dbClient->queryRow(`SELECT SUPPLIERID FROM SUPPLIER WHERE SHORTNAME=${supplier};`);
            if (supplierID is error) {
                errorMessages = errorMessages + string `Line:${csvLineNo}| ${supplier} is missing in SUPPLIER table
`;
                hasError = true;
            } else {
                quotationSupplierId = supplierID;
            }
            if (!hasError) {
                Quotation quotation = {
                    supplierID: quotationSupplierId,
                    itemID: medicalItemId,
                    brandName,
                    availableQuantity,
                    period: check getPeriod(period),
                    expiryDate: check getDateFromString(expiryDate),
                    regulatoryInfo,
                    unitPrice
                };
                qutoations.push(quotation);
            }
        }
        else {
            log:printError(string `Invalid CSV Length in line:${csvLineNo}`);
        }
    }
    if (errorMessages.length() > 0) {
        return error(errorMessages);
    }
    return qutoations;
}

function updateMedicalNeedsTable(MedicalNeed[] medicalNeeds) returns error? {
    MedicalNeed[] needsRequireUpdate = [];
    MedicalNeed[] newMedicalNeed = [];
    foreach MedicalNeed medicalNeed in medicalNeeds {
        int|error needID = dbClient->queryRow(`SELECT NEEDID FROM MEDICAL_NEED 
                                    WHERE ITEMID=${medicalNeed.itemID} AND BENEFICIARYID =${medicalNeed.beneficiaryID} 
                                    AND PERIOD=${medicalNeed.period}`);
        if (needID is int) {
            needsRequireUpdate.push(medicalNeed);
        } else {
            newMedicalNeed.push(medicalNeed);
        }
    }
    log:printInfo(string `Total Medical Needs Count:${medicalNeeds.length()}|
                          Requre Update:${needsRequireUpdate.length()} |New Needs:${newMedicalNeed.length()}`);
    sql:ParameterizedQuery[] insertQueries =
        from var data in newMedicalNeed
    select `INSERT INTO MEDICAL_NEED 
                (ITEMID, BENEFICIARYID, PERIOD, NEEDEDQUANTITY, REMAININGQUANTITY, URGENCY) 
                VALUES (${data.itemID}, ${data.beneficiaryID},
                ${data.period}, ${data.neededQuantity}, 0, ${data.urgency})`;

    sql:ParameterizedQuery[] updateQueries =
        from var data in needsRequireUpdate
    select `UPDATE MEDICAL_NEED 
                SET NEEDEDQUANTITY = ${data.neededQuantity},
                REMAININGQUANTITY = 0 ,
                URGENCY = ${data.urgency} 
                WHERE ITEMID = ${data.itemID} AND BENEFICIARYID = ${data.beneficiaryID} AND PERIOD = ${data.period}`;

    transaction {
        var insertResult = dbClient->batchExecute(insertQueries);
        var updateResult = dbClient->batchExecute(updateQueries);
        if insertResult is sql:BatchExecuteError || updateResult is sql:BatchExecuteError {
            rollback;
            return error("Transaction Failed"); //TODO:Add more detailed error
        } else {
            error? err = commit;
            if err is error {
                return error("Error occurred while committing"); //TODO:Add more detailed error
            }
        }
    }
}

function updateQuotationsTable(Quotation[] quotations) returns error? {
    Quotation[] quotationsRequireUpdate = [];
    Quotation[] newquotations = [];
    foreach Quotation quotation in quotations {
        int|error quotationID = dbClient->queryRow(`SELECT QUOTATIONID FROM QUOTATION 
                                    WHERE ITEMID=${quotation.itemID} AND SUPPLIERID =${quotation.supplierID} 
                                    AND PERIOD=${quotation.period} AND BRANDNAME =${quotation.brandName}`);
        if (quotationID is int) {
            quotationsRequireUpdate.push(quotation);
        } else {
            newquotations.push(quotation);
        }
    }
    log:printInfo(string `Total Quotations Count:${quotations.length()}|
                          Requre Update:${quotationsRequireUpdate.length()} |New Quotations:${newquotations.length()}`);
    sql:ParameterizedQuery[] insertQueries =
        from var data in newquotations
    select `INSERT INTO QUOTATION 
                (SUPPLIERID, ITEMID, BRANDNAME, AVAILABLEQUANTITY, PERIOD, EXPIRYDATE, UNITPRICE, REGULATORYINFO) 
                VALUES (${data.supplierID}, ${data.itemID},${data.brandName}, ${data.availableQuantity}, ${data.period}, 
                ${data.expiryDate}, ${data.unitPrice}, ${data.regulatoryInfo})`;

    sql:ParameterizedQuery[] updateQueries =
        from var data in quotationsRequireUpdate
    select `UPDATE QUOTATION 
                SET AVAILABLEQUANTITY = ${data.availableQuantity},
                EXPIRYDATE = ${data.expiryDate},
                UNITPRICE = ${data.unitPrice}, 
                REGULATORYINFO = ${data.regulatoryInfo}
                WHERE ITEMID = ${data.itemID} AND SUPPLIERID = ${data.supplierID} AND PERIOD = ${data.period} 
                AND BRANDNAME =${data.brandName}`;

    transaction {
        var insertResult = dbClient->batchExecute(insertQueries);
        var updateResult = dbClient->batchExecute(updateQueries);
        if insertResult is sql:BatchExecuteError || updateResult is sql:BatchExecuteError {
            rollback;
            return error("Transaction Failed"); //TODO:Add more detailed error

        } else {
            error? err = commit;
            if err is error {
                return error("Error occurred while committing"); //TODO:Add more detailed error
            }
        }
    }
}

function getPeriod(string period) returns time:Date|error {
    string[] dateParts = regex:split(period, " ");
    int year = check int:fromString(dateParts[1]);
    int month = check getMonth(dateParts[0]);
    time:Date date = {year: year, month: month, day: 1};
    return date;
}

function getMonth(string month) returns int|error {
    match month {
        "Jan" => {
            return 1;
        }
        "Feb" => {
            return 2;
        }
        "Mar" => {
            return 3;
        }
        "Apr" => {
            return 4;
        }
        "May" => {
            return 5;
        }
        "Jun" => {
            return 6;
        }
        "Jul" => {
            return 7;
        }
        "Aug" => {
            return 8;
        }
        "Sep" => {
            return 9;
        }
        "Oct" => {
            return 10;
        }
        "Nov" => {
            return 11;
        }
        "Dec" => {
            return 12;
        }
        _ => {
            return error("Invalid month in the Period");
        }
    }
}

function getDateFromString(string dateString) returns time:Date|error {
    string[] dateParts = regex:split(dateString, "/");
    time:Date date = {
        year: check int:fromString(dateParts[2]),
        month: check int:fromString(dateParts[0]),
        day: check int:fromString(dateParts[1])
    };
    return date;
}

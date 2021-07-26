import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/os;

const CONFIG_JSON_PATH = "./resources/connectors.json";
const GITHUB_API_PATH = "https://api.github.com/repos/lakshanss";//need to change to ballerina-platform
const ACCEPT_HEADER_KEY = "Accept";
const ACCEPT_HEADER_VALUE = "application/vnd.github.v3+json";
const DISPATCHES = "/dispatches";
const RELEASE_EVENT = "connector-release-pipeline";

json configJson = check getConfigJson();
final string ballerinaDistVersion = <string> check configJson.ballerinaDistVersion;
final string ballerinaLangVersion = <string> check configJson.ballerinaLangVersion;

string & readonly githubAccessToken = os:getEnv("BALLERINA_BOT_TOKEN");
http:BearerTokenConfig bearerTokenConfig = {token: githubAccessToken};
final http:Client httpClient = check new (GITHUB_API_PATH, {auth: bearerTokenConfig});

public function main() returns error? {
    log:printInfo("Ballerina Distribution : " + ballerinaDistVersion);
    log:printInfo("Ballerina Lang Version : " + ballerinaLangVersion);

    // Read connector list from config json
    json[] connectors = <json[]> check configJson.connectors;
    Connector[] connectorList = check getConnectorsArray(connectors);

    foreach Connector connector in connectorList {
        if (connector.release) {
            triggerConnectorRelease(connector);
        }
    }
}

isolated function triggerConnectorRelease(Connector connector) {
    log:printInfo("Triggering release of " + connector.name + connector.'version);
    http:Request request = new();
    string path = "/" + connector.name + DISPATCHES;
    request.setHeader(ACCEPT_HEADER_KEY, ACCEPT_HEADER_VALUE);
    json payload = {
        event_type: RELEASE_EVENT,
        client_payload: {
            connectorVersion: connector.'version,
            ballerinaDistVersion: ballerinaDistVersion,
            ballerinaLangVersion: ballerinaLangVersion
        }
    };
    request.setJsonPayload(payload);
    http:Response|error response = httpClient->post(path, request);
    validateResponse(response, connector.name);
}

isolated function validateResponse(http:Response|error response, string connectorName) {
    if (response is error) {
        log:printError("Error while triggering release of " + connectorName + " " + response.toString());
    } else {
        if (validateStatusCode(response.statusCode)) {
            log:printInfo("Successfully triggered release of " + connectorName);
        } else {
            log:printError("Failed to trigger release of " + connectorName + " - Status code: " + 
                response.statusCode.toString());
        }
    }
}

isolated function validateStatusCode(int statusCode) returns boolean {
    if (statusCode != 200 && statusCode != 201 && statusCode != 202 && statusCode != 204) {
        return false;
    }
    return true;
}

isolated function getConnectorsJsonArray() returns json[] | error {
    json configJson = check io:fileReadJson(CONFIG_JSON_PATH); 
    return <json[]> check configJson.connectors;
}

isolated function getConfigJson() returns json | error {
    return check io:fileReadJson(CONFIG_JSON_PATH); 
}

isolated function getConnectorsArray(json[] connectorsJsonArr) returns Connector[] | error {
    Connector[] connectors = [];
    foreach json c in connectorsJsonArr {
        Connector connector = check c.cloneWithType(Connector);
        connectors.push(connector);
    }
    return connectors;
}

type Connector record {
    string name;
    string 'version;
    boolean release;
};

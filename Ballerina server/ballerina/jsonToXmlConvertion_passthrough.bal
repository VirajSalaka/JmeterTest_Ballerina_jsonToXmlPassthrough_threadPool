import ballerina.net.http;

@http:configuration {basePath:"/passthrough"}
service<http> passthrough {

   @http:resourceConfig {
       methods:["POST"],
       path:"/"
   }
   resource passthrough (http:Request req, http:Response res) {
        endpoint<http:HttpClient> nyseEP {
		create http:HttpClient("http://localhost:8688", {});
	}

	json jsonPayload = req.getJsonPayload();


	http:Request req2 = {};
        xml xmlPayload = jsonPayload.toXML({}); 

        req2.setXmlPayload(xmlPayload);
        
	http:HttpConnectorError errorMsg;

	http:Response res2;
        res2, errorMsg = nyseEP.post("/echo", req2);
	
        xml backendResponse = res2.getXmlPayload();

	res.setXmlPayload(backendResponse);
        res.send();
   }
}

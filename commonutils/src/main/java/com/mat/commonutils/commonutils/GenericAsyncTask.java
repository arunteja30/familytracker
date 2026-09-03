package com.mat.commonutils.commonutils;


import com.android.volley.AuthFailureError;
import com.android.volley.Response;
import com.android.volley.toolbox.JsonObjectRequest;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class GenericAsyncTask extends JsonObjectRequest {
    private String serverKey = "key=AAAAHwHMedc:APA91bGkAKpJjSxEwq48z7GbV5b57ug3_HfjezaoIZlAOgYvbytfm1AqxCzPGeYo3evgf5gILFjVGlCOcdSmHRCvHWN0DoCyyBrvQnmj35mY0sVfoGh8fIr4FiU6E_L0QXQEFTAEBXMV";
    private Map<String, String> headers = new HashMap<>();

    // Since we're extending a Request class
    // we just use its constructor
    public GenericAsyncTask(int method, String url, JSONObject jsonRequest,
                            Response.Listener<JSONObject> listener, Response.ErrorListener errorListener) {
        super(method, url, jsonRequest, listener, errorListener);
    }

    /**
     * Custom class!
     */
    public void setCookies(List<String> cookies) {
        StringBuilder sb = new StringBuilder();
        for (String cookie : cookies) {
            sb.append(cookie).append("; ");
        }
        headers.put("Cookie", sb.toString());
    }

    @Override
    public Map<String, String> getHeaders() throws AuthFailureError {
        headers.put("Authorization", serverKey);
        headers.put("Content-Type", "application/json");
        return headers;
    }


}

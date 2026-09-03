package com.mat.commonutils.commonutils;

import android.util.Base64;

import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

public class AESHandler {
    private static final AESHandler ourInstance = new AESHandler();

    private AESHandler() {
    }

    public static AESHandler getInstance() {
        return ourInstance;
    }

    public String getEncryptedData(String stringToEncrypt) {
        String finalData = "";

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            byte[] data = stringToEncrypt.getBytes(StandardCharsets.UTF_16LE);

            try {
                Rfc2898DeriveBytes pdb = new Rfc2898DeriveBytes(Constants.ENCRYPTED_KEY, new byte[]{0x49, 0x76, 0x61, 0x6e, 0x20, 0x4d, 0x65, 0x64, 0x76, 0x65, 0x64, 0x65, 0x76});
                byte[] key = pdb.GetBytes(32);
                byte[] IV = pdb.GetBytes(16);
                SecretKey keyspecs = new SecretKeySpec(key, "AES");
                IvParameterSpec iv = new IvParameterSpec(IV);
                Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
                cipher.init(Cipher.ENCRYPT_MODE, keyspecs, iv);
                byte[] encVal = cipher.doFinal(data);
                finalData = Base64.encodeToString(encVal, Base64.NO_WRAP);
//                System.out.println("needed...: A6ZDqwDGWZoeYl3vcDwM9z60aput7as7iDIf00d/X8g=");
                System.out.println("   got...: " + finalData);
            } catch (NoSuchAlgorithmException e) {
                e.printStackTrace();
            } catch (InvalidKeyException e) {
                e.printStackTrace();
            } catch (UnsupportedEncodingException e) {
                e.printStackTrace();
            } catch (Exception e) {
                e.printStackTrace();
            }

        }
        return finalData;
    }

    public String getDecryptData(String StringToDecrypt) {
        String finalData = "";

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            byte[] data = Base64.decode(StringToDecrypt, Base64.NO_WRAP);
            try {
                Rfc2898DeriveBytes pdb = new Rfc2898DeriveBytes(Constants.ENCRYPTED_KEY, new byte[]{0x49, 0x76, 0x61, 0x6e, 0x20, 0x4d, 0x65, 0x64, 0x76, 0x65, 0x64, 0x65, 0x76});
                byte[] key = pdb.GetBytes(32);
                byte[] IV = pdb.GetBytes(16);


                SecretKey keyspecs = new SecretKeySpec(key, "AES");
                IvParameterSpec iv = new IvParameterSpec(IV);
                Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
                cipher.init(Cipher.DECRYPT_MODE, keyspecs, iv);
                finalData = new String(cipher.doFinal(data));
                finalData = Base64.encodeToString(Base64.decode(finalData, Base64.DEFAULT), Base64.NO_WRAP);
                System.out.println("decrypt - needed...: username");
                System.out.println("decrypt - got...: " + finalData.trim());

            } catch (NoSuchAlgorithmException e) {
                e.printStackTrace();
            } catch (InvalidKeyException e) {
                e.printStackTrace();
            } catch (UnsupportedEncodingException e) {
                e.printStackTrace();
            } catch (Exception e) {
                e.printStackTrace();
            }

        }
        return finalData;
    }

}

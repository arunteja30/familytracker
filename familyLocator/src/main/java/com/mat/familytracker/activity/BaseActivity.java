package com.mat.familytracker.activity;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.location.Location;
import android.os.Bundle;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.navigation.NavigationView;
import com.google.android.material.snackbar.Snackbar;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import androidx.appcompat.app.ActionBarDrawerToggle;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;

import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.MapFragment;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.model.BitmapDescriptorFactory;
import com.google.android.gms.maps.model.CameraPosition;
import com.google.android.gms.maps.model.LatLng;
import com.google.android.gms.maps.model.Marker;
import com.google.android.gms.maps.model.MarkerOptions;
import com.google.android.gms.maps.model.Polyline;
import com.google.android.gms.maps.model.PolylineOptions;
import com.mat.familytracker.R;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerListener;
import com.mat.familytracker.gpstracker.LatLong;
import com.mat.familytracker.gpstracker.LocationFetchListener;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.LatLngInterpolator;
import com.mat.familytracker.utils.MarkerAnimation;

import java.util.ArrayList;
import java.util.List;


public class BaseActivity extends AppCompatActivity
        implements NavigationView.OnNavigationItemSelectedListener {
    public static final int MY_PERMISSIONS_REQUEST_LOCATION = 99;
    public static final int MY_PERMISSIONS_REQUEST_LOCATION_2 = 199;
    private GoogleMap googleMap;
    // latitude and longitude
    double latitude;
    double longitude;
    private String currentAddress;
    private GoogleMap mGoogleMap;
    private List<LatLong> locationsList;
    private Marker ourGlobalMarker;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_base);
        Toolbar toolbar = (Toolbar) findViewById(R.id.toolbar);
        final Button startTracker = (Button) findViewById(R.id.start_tracker);
        final Button stopTracker = (Button) findViewById(R.id.stop_tracker);
//        setSupportActionBar(toolbar);
        checkLocationPermission();
        if (locationsList == null) {
            locationsList = new ArrayList<>();
        }
        startTracker.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                GPSHandler.getInstance().startGPSTracker(BaseActivity.this, Constants.MIN_DISTANCE_OF_TRACKING, Constants.MIN_TIME_OF_TRACKING, new LocationFetchListener() {
                    @Override
                    public void onLocationFetched(LatLong latLong) {
                        if (mGoogleMap != null) {
                            MarkerOptions marker = new MarkerOptions().position(new LatLng(latLong.getLatitude(), latLong.getLongitude())).title(currentAddress);
                            marker.icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE));
                            locationsList.add(latLong);
//                            drawPolyLine(mGoogleMap);
                            // adding marker
                            if (ourGlobalMarker == null) { // First time adding marker to map
                                ourGlobalMarker = mGoogleMap.addMarker(marker);
                            } else {
                                MarkerAnimation.animateMarkerToICS(ourGlobalMarker, new LatLng(latLong.getLatitude(), latLong.getLongitude()), new LatLngInterpolator.Spherical());
                            }


                        }
                    }
                });
                startTracker.setEnabled(false);
            }
        });
        stopTracker.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                GPSHandler.getInstance().stopGPSTracker(BaseActivity.this);
                startTracker.setEnabled(true);
            }
        });
        final FloatingActionButton fab = (FloatingActionButton) findViewById(R.id.fab);
        FloatingActionButton fab_add_family = (FloatingActionButton) findViewById(R.id.fab_add_family);
        fab_add_family.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                Intent family = new Intent(BaseActivity.this, AddFamilyActivity.class);
                startActivity(family);
            }
        });
        fab.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                Snackbar.make(view, "Fetching Latest Location..", Snackbar.LENGTH_LONG)
                        .setAction("Action", null).show();

                GPSHandler.getInstance().getCurrentLocation(BaseActivity.this, new GPSTrackerListener() {
                    @Override
                    public void onLocationFetched(Location location) {
                        Double latitude = location.getLatitude();
                        Double longitude = location.getLongitude();

                        initializeMap(location);

                    }
                });
            }

        });

        DrawerLayout drawer = (DrawerLayout) findViewById(R.id.drawer_layout);
        ActionBarDrawerToggle toggle = new ActionBarDrawerToggle(
                this, drawer, toolbar, R.string.navigation_drawer_open, R.string.navigation_drawer_close);
        drawer.addDrawerListener(toggle);
        toggle.syncState();

        NavigationView navigationView = (NavigationView) findViewById(R.id.nav_view);
        navigationView.setNavigationItemSelectedListener(this);
    }


    private void drawPolyLine(GoogleMap mGoogleMap) {

        if (locationsList != null) {


            PolylineOptions options = new PolylineOptions().width(5).color(Color.BLUE).geodesic(true);
            for (int z = 0; z < locationsList.size(); z++) {
                LatLng point = new LatLng(locationsList.get(z).getLatitude(), locationsList.get(z).getLongitude());
                options.add(point);
                moveCameraPosition(locationsList.get(z).getLatitude(), locationsList.get(z).getLongitude(), googleMap);
            }
            Polyline line = mGoogleMap.addPolyline(options);

        }


    }

    public void moveCameraPosition(double latitude, double longitude, GoogleMap googleMap) {
        CameraPosition cameraPosition = new CameraPosition.Builder().target(new LatLng(latitude, longitude)).zoom(15).build();
        googleMap.animateCamera(CameraUpdateFactory.newCameraPosition(cameraPosition));
    }

    public void initializeMap(final Location location) {

        ((MapFragment) getFragmentManager().findFragmentById(R.id.google_map)).getMapAsync(new OnMapReadyCallback() {
            @Override
            public void onMapReady(GoogleMap googleMap) {
                mGoogleMap = googleMap;
                // create marker
                MarkerOptions marker = new MarkerOptions().position(new LatLng(location.getLatitude(), location.getLongitude())).title(currentAddress);
                // adding marker
                mGoogleMap.addMarker(marker);
                mGoogleMap.setMapType(GoogleMap.MAP_TYPE_NORMAL);
                CameraPosition cameraPosition = new CameraPosition.Builder().target(new LatLng(location.getLatitude(), location.getLongitude())).zoom(12).build();

                mGoogleMap.animateCamera(CameraUpdateFactory.newCameraPosition(cameraPosition));
                if (ActivityCompat.checkSelfPermission(BaseActivity.this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(BaseActivity.this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                    mGoogleMap.setMyLocationEnabled(true); // false to disable
                }

                marker.icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN));

                mGoogleMap.addMarker(marker);
                mGoogleMap.getUiSettings().setZoomControlsEnabled(false); // true to enable
            }
        });

        // check if map is created successfully or not


    }

    public void checkLocationPermission() {
        if (ContextCompat.checkSelfPermission(this,
                Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,
                    new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, MY_PERMISSIONS_REQUEST_LOCATION);
        }
    }


    @Override
    public void onBackPressed() {
        DrawerLayout drawer = (DrawerLayout) findViewById(R.id.drawer_layout);
        if (drawer != null && drawer.isDrawerOpen(GravityCompat.START)) {
            drawer.closeDrawer(GravityCompat.START);
        } else {
            super.onBackPressed();
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.base, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        // Handle action bar item clicks here. The action bar will
        // automatically handle clicks on the Home/Up button, so long
        // as you specify a parent com.mat.familytracker.activity in AndroidManifest.xml.
        int id = item.getItemId();

        //noinspection SimplifiableIfStatement
        if (id == R.id.action_settings) {
            return true;
        }

        return super.onOptionsItemSelected(item);
    }

    @SuppressWarnings("StatementWithEmptyBody")
    @Override
    public boolean onNavigationItemSelected(MenuItem item) {
        // Handle navigation view item clicks here.
        int id = item.getItemId();

        if (id == R.id.nav_camera) {
            // Handle the camera action
        } else if (id == R.id.nav_gallery) {

        } else if (id == R.id.nav_slideshow) {

        } else if (id == R.id.nav_manage) {

        } else if (id == R.id.nav_share) {

        } else if (id == R.id.nav_send) {

        }

        DrawerLayout drawer = (DrawerLayout) findViewById(R.id.drawer_layout);
        drawer.closeDrawer(GravityCompat.START);
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
                                           String permissions[], int[] grantResults) {
        switch (requestCode) {
            case MY_PERMISSIONS_REQUEST_LOCATION: {
                // If request is cancelled, the result arrays are empty.
                if (grantResults.length > 0
                        && grantResults[1] == PackageManager.PERMISSION_GRANTED) {

                    // permission was granted, yay! Do the
                    // location-related task you need to do.
                    if (ContextCompat.checkSelfPermission(this,
                            Manifest.permission.ACCESS_FINE_LOCATION)
                            == PackageManager.PERMISSION_GRANTED) {
                        getCurrentLocation();
                    }

                } else {

                    // permission denied, boo! Disable the
                    // functionality that depends on this permission.
                    ActivityCompat.requestPermissions(this,
                            new String[]{Manifest.permission.ACCESS_FINE_LOCATION},
                            MY_PERMISSIONS_REQUEST_LOCATION);

                }
                return;
            }
        }
    }

    private void getCurrentLocation() {
        GPSHandler.getInstance().getCurrentLocation(this, new GPSTrackerListener() {
            @Override
            public void onLocationFetched(Location location) {
                Double latitude = location.getLatitude();
                Double longitude = location.getLongitude();
                initializeMap(location);
                System.out.print("arun current location is : " + "latitude : " + latitude + "\n" +
                        "longitude : " + longitude);

            }
        });
    }


}




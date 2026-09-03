package com.mat.familytracker.activity;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.graphics.drawable.Drawable;
import android.location.Address;
import android.location.Geocoder;
import android.location.Location;
import android.os.Bundle;
import androidx.annotation.DrawableRes;
import androidx.core.content.ContextCompat;
import androidx.appcompat.app.AppCompatActivity;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.MapFragment;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.model.BitmapDescriptorFactory;
import com.google.android.gms.maps.model.CameraPosition;
import com.google.android.gms.maps.model.LatLng;
import com.google.android.gms.maps.model.Marker;
import com.google.android.gms.maps.model.MarkerOptions;
import com.google.android.gms.maps.model.PointOfInterest;
import com.google.android.gms.maps.model.Polyline;
import com.google.android.gms.maps.model.PolylineOptions;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.ImageSaver;
import com.mat.familytracker.Database.LogsEntity;
import com.mat.familytracker.Database.Repository;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.domain.LocationDetailsModel;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerListener;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.LatLngInterpolator;
import com.mat.familytracker.utils.MarkerAnimation;

import java.util.List;

public class MapActivity extends AppCompatActivity implements GoogleMap.OnInfoWindowClickListener, GoogleMap.OnPoiClickListener {

    private Marker userMarker;
    private String currentAddress = "not availble";
    private GoogleMap mGooglemap;
    private Polyline mPolyLine;
    MapCustomInfoAdapter customInfoWindow;
    private static final int ANIMATE_SPEEED = 1500;
    private static final int ANIMATE_SPEEED_TURN = 1000;
    private static final int BEARING_OFFSET = 20;
    private LinearLayout map_ll_search;
    private TextView txt_alert_message;
    FamilyMemberModel familyMemberModel;
    Bitmap userImage;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_map);
        setupActionBar();
//        checkLocationPermission();
        map_ll_search = (LinearLayout) findViewById(R.id.map_ll_search);
        txt_alert_message = (TextView) findViewById(R.id.txt_alert_message);
        initializeMap();

    }

    private void setupActionBar() {
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
        }
    }

    private void initializeMap() {
        ((MapFragment) getFragmentManager().findFragmentById(R.id.map_activity)).getMapAsync(new OnMapReadyCallback() {
            @Override
            public void onMapReady(final GoogleMap googleMap) {
                mGooglemap = googleMap;
                if (ContextCompat.checkSelfPermission(MapActivity.this,
                        Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED) {
                    if (mGooglemap != null) {
                        mGooglemap.setMyLocationEnabled(true);
                    }
                    mGooglemap.setOnMyLocationButtonClickListener(new GoogleMap.OnMyLocationButtonClickListener() {
                        @Override
                        public boolean onMyLocationButtonClick() {
                            GPSHandler.getInstance().getCurrentLocation(MapActivity.this, new GPSTrackerListener() {
                                @Override
                                public void onLocationFetched(Location location) {
                                    Toast.makeText(MapActivity.this, "moving to your current location", Toast.LENGTH_SHORT).show();
                                    moveCameraPosition(location.getLatitude(), location.getLongitude(), mGooglemap);
                                }
                            });
                            return false;
                        }
                    });
                }
                googleMap.setOnPoiClickListener(MapActivity.this);
                familyMemberModel = (FamilyMemberModel) getIntent().getSerializableExtra(Constants.FAMILY_MEM_MODEL);
                googleMap.getUiSettings().setZoomControlsEnabled(true);
                googleMap.setMinZoomPreference(5);
                googleMap.setMaxZoomPreference(11115);
                FirebaseHandler.getInstance().getLocationDetailsOfUser(familyMemberModel.getMobile(), new CommonListener() {
                    @Override
                    public void onTaskCompleted(Object locationData) {
                        final LocationDetailsModel locationDetailsModel = (LocationDetailsModel) locationData;
                        if (locationDetailsModel != null) {
                            final LatLng location = new LatLng(locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude());

                            MarkerOptions marker = new MarkerOptions().position(location).title(familyMemberModel.getName());
                            setTitle(familyMemberModel.getName().toUpperCase());
                            GPSHandler.getInstance().getAddressFromLocation(MapActivity.this, locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude(), new CommonListener() {
                                @Override
                                public void onTaskCompleted(Object value) {
                                    Repository repository = new Repository(MapActivity.this);
                                    repository.Insert(new LogsEntity(locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude(),
                                            CommonUtils.getInstance().getCurrentTime(locationDetailsModel.getTimeStamp()), locationDetailsModel.getGpsStatus(),
                                            value.toString(), familyMemberModel.getMobile()));
                                }
                            });
                            if (locationDetailsModel.getMessage() != null)
                                txt_alert_message.setText(locationDetailsModel.getMessage());
//                            userMarker = googleMap.addMarker(marker);
//                            moveCameraPosition(locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude(), googleMap);
//                            if (userMarker == null) { // First time adding marker to map
//                                marker.icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED));
//                                Marker startMarker = googleMap.addMarker(marker);
//                                startMarker.setIcon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN));
//                                userMarker = googleMap.addMarker(marker);
//
//                            } else {
//                                Marker endMarker = googleMap.addMarker(marker);
//                                endMarker.setIcon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE));
//
//                            }
                            if (userMarker == null) {
                                Marker startMarker = googleMap.addMarker(marker);
                                startMarker.setIcon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN));
                                userMarker = addCustomMarker(googleMap, location, familyMemberModel);
                                setupCameraPositionForMovement(userMarker.getPosition(), location);
                            } else {
                                MarkerOptions markerStops = new MarkerOptions().position(userMarker.getPosition()).title(familyMemberModel.getName());
                                Marker startMarker = googleMap.addMarker(markerStops);
                                startMarker.setSnippet("click for address..");
                                startMarker.setIcon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE));
                                setupCameraPositionForMovement(userMarker.getPosition(), location);

                            }


                            userMarker.setSnippet("click for address..");
                            customInfoWindow = new MapCustomInfoAdapter(MapActivity.this, locationDetailsModel);
                            googleMap.setInfoWindowAdapter(customInfoWindow);

//                            userMarker.showInfoWindow();
                            if (userMarker.isInfoWindowShown()) {
                                userMarker.hideInfoWindow();
                            }

                            googleMap.setOnInfoWindowClickListener(MapActivity.this);

                        }
                    }
                });
            }

        });

    }

    public void drawPolyline(GoogleMap map, LatLng currentPosition, LatLng farEndPosition) {

        PolylineOptions polylineOptions = new PolylineOptions().add(currentPosition).add(farEndPosition).width(5).color(Color.BLACK);
        mPolyLine = map.addPolyline(polylineOptions);
    }

    @Override
    public void onInfoWindowClick(final Marker marker) {

        LatLng location = marker.getPosition();

        GPSHandler.getInstance().getAddressFromLocation(MapActivity.this, location.latitude, location.longitude, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    System.out.println("arunnnnnlocation address: " + value.toString());
                    marker.setSnippet(value.toString());
                    marker.showInfoWindow();
                }
            }
        });
    }

    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.map_type_menu, menu);
        return true;
    }

    public void onMapSearch(View view) {
        EditText locationSearch = (EditText) findViewById(R.id.editText);
        String location = locationSearch.getText().toString();
        List<Address> addressList = null;

        if (location != null || !location.equals("")) {
            Geocoder geocoder = new Geocoder(this);
            try {
                addressList = geocoder.getFromLocationName(location, 1);
                Address address = addressList.get(0);
                LatLng latLng = new LatLng(address.getLatitude(), address.getLongitude());
                mGooglemap.addMarker(new MarkerOptions().position(latLng).title(location));
                mGooglemap.animateCamera(CameraUpdateFactory.newLatLng(latLng));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    public void moveCameraPosition(double latitude, double longitude, GoogleMap googleMap) {
        float zoomLevel = googleMap.getCameraPosition().zoom;
        if (zoomLevel < 14) {
            zoomLevel = 14;
        }
        CameraPosition cameraPosition = new CameraPosition.Builder().target(new LatLng(latitude, longitude)).zoom(zoomLevel).build();
        googleMap.animateCamera(CameraUpdateFactory.newCameraPosition(cameraPosition));
    }

    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
        }
        if (mGooglemap != null) {
            switch (item.getItemId()) {
                case R.id.map_normal:
                    mGooglemap.setMapType(GoogleMap.MAP_TYPE_NORMAL);
                    break;
                case R.id.map_satellite:
                    mGooglemap.setMapType(GoogleMap.MAP_TYPE_SATELLITE);
                    break;
                case R.id.map_terrain:
                    mGooglemap.setMapType(GoogleMap.MAP_TYPE_TERRAIN);
                    break;
                case R.id.map_hybrid:
                    mGooglemap.setMapType(GoogleMap.MAP_TYPE_HYBRID);
                    break;
                case R.id.location_history:
                    Intent history = new Intent(MapActivity.this, LocationHistoryDetailsActivity.class);
                    history.putExtra("USER", familyMemberModel.getMobile());
                    startActivity(history);
                    break;
                case R.id.map_search:
                    if (map_ll_search.getVisibility() == View.VISIBLE) {
                        map_ll_search.setVisibility(View.GONE);
                    } else {
                        map_ll_search.setVisibility(View.VISIBLE);

                    }
                    break;
                case R.id.map_traffic:
                    if (item.getTitle().equals("Show Traffic")) {
                        mGooglemap.setTrafficEnabled(true);
                        item.setTitle("Hide Traffic");
                    } else {
                        mGooglemap.setTrafficEnabled(false);
                    }

                    break;
            }
        }
        return true;
    }

    private void setupCameraPositionForMovement(final LatLng markerPos, final LatLng secondPos) {

        float bearing = bearingBetweenLatLngs(markerPos, secondPos);
//        float bearing = 40;


        CameraPosition cameraPosition = new CameraPosition.Builder()
                .target(secondPos)
                .bearing(bearing + BEARING_OFFSET)
                .tilt(30)
                .zoom(mGooglemap.getCameraPosition().zoom >= 13 ? mGooglemap.getCameraPosition().zoom : 15)
                .build();

        mGooglemap.animateCamera(CameraUpdateFactory.newCameraPosition(cameraPosition),
                ANIMATE_SPEEED_TURN,
                new GoogleMap.CancelableCallback() {

                    @Override
                    public void onFinish() {
                        System.out.println("finished camera");
                        MarkerAnimation.animateMarkerToICS(userMarker, secondPos, new LatLngInterpolator.Spherical());
                        drawPolyline(mGooglemap, userMarker.getPosition(), secondPos);
                    }

                    @Override
                    public void onCancel() {
                        System.out.println("cancelling camera");
                    }
                }
        );
    }

    @Override
    public void onPoiClick(PointOfInterest poi) {
        Toast.makeText(getApplicationContext(), "Clicked: " +
                        poi.name,
                Toast.LENGTH_SHORT).show();
    }

    private Location convertLatLngToLocation(LatLng latLng) {
        Location loc = new Location("someLoc");
        loc.setLatitude(latLng.latitude);
        loc.setLongitude(latLng.longitude);
        return loc;
    }

    private float bearingBetweenLatLngs(LatLng begin, LatLng end) {
        Location beginL = convertLatLngToLocation(begin);
        Location endL = convertLatLngToLocation(end);

        return beginL.bearingTo(endL);
    }

    private Marker addCustomMarker(GoogleMap mGooglemap, LatLng location, FamilyMemberModel familyMember) {
        Log.d("Cutom marker", "addCustomMarker()");
        // adding a marker on map with image from  drawable
        if (userImage == null) {
            ImageSaver imageSaver = new ImageSaver(this);
            userImage = imageSaver.loadBitmap(this, familyMember.getMobile());
        }
        String name = CommonUtils.getInstance().getMyName(familyMember);
        if (userImage != null) {
            return mGooglemap.addMarker(new MarkerOptions()
                    .position(location)
//                    .icon(BitmapDescriptorFactory.fromBitmap(bitmap)));
                    .icon(BitmapDescriptorFactory.fromBitmap(getMarkerBitmapFromView(userImage, name))));
        } else {
            return mGooglemap.addMarker(new MarkerOptions()
                    .position(location)
                    .icon(BitmapDescriptorFactory.fromBitmap(getMarkerBitmapFromView(R.drawable.blank_profile_picture, name))));
        }
    }

    private Bitmap getMarkerBitmapFromView(Bitmap bitmap, String familyMemberName) {
        View customMarkerView = ((LayoutInflater) getSystemService(Context.LAYOUT_INFLATER_SERVICE)).inflate(R.layout.view_custom_marker, null);
        ImageView markerImageView = (ImageView) customMarkerView.findViewById(R.id.profile_image);
        TextView title = customMarkerView.findViewById(R.id.txt_name);
        title.setText(familyMemberName.toUpperCase());
        markerImageView.setImageBitmap(bitmap);
        customMarkerView.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED);
        customMarkerView.layout(0, 0, customMarkerView.getMeasuredWidth(), customMarkerView.getMeasuredHeight());
        customMarkerView.buildDrawingCache();
        Bitmap returnedBitmap = Bitmap.createBitmap(customMarkerView.getMeasuredWidth(), customMarkerView.getMeasuredHeight(),
                Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(returnedBitmap);
        canvas.drawColor(Color.WHITE, PorterDuff.Mode.SRC_IN);
        Drawable drawable = customMarkerView.getBackground();
        if (drawable != null)
            drawable.draw(canvas);
        customMarkerView.draw(canvas);
        return returnedBitmap;
    }

    private Bitmap getMarkerBitmapFromView(@DrawableRes int resId, String familyMemberName) {

        View customMarkerView = ((LayoutInflater) getSystemService(Context.LAYOUT_INFLATER_SERVICE)).inflate(R.layout.view_custom_marker, null);
        ImageView markerImageView = (ImageView) customMarkerView.findViewById(R.id.profile_image);
        markerImageView.setImageResource(resId);
        TextView title = customMarkerView.findViewById(R.id.txt_name);
        title.setText(familyMemberName.toUpperCase());
        customMarkerView.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED);
        customMarkerView.layout(0, 0, customMarkerView.getMeasuredWidth(), customMarkerView.getMeasuredHeight());
        customMarkerView.buildDrawingCache();
        Bitmap returnedBitmap = Bitmap.createBitmap(customMarkerView.getMeasuredWidth(), customMarkerView.getMeasuredHeight(),
                Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(returnedBitmap);
        canvas.drawColor(Color.WHITE, PorterDuff.Mode.SRC_IN);
        Drawable drawable = customMarkerView.getBackground();
        if (drawable != null)
            drawable.draw(canvas);
        customMarkerView.draw(canvas);
        return returnedBitmap;
    }
}

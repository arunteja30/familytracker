package com.mat.familytracker.activity;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.graphics.drawable.Drawable;
import android.location.Location;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.DrawableRes;
import androidx.core.content.ContextCompat;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.ImageView;
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
import com.google.maps.android.ui.IconGenerator;
import com.mat.commonutils.commonutils.CommonListener;
import com.mat.commonutils.commonutils.ImageSaver;
import com.mat.commonutils.dialogs.AestheticDialog;
import com.mat.commonutils.recyclerview.BaseRecyclerListener;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;
import com.mat.familytracker.domain.LocationDetailsModel;
import com.mat.familytracker.gpstracker.GPSHandler;
import com.mat.familytracker.gpstracker.GPSTrackerListener;
import com.mat.familytracker.utils.CommonUtils;
import com.mat.familytracker.utils.Constants;
import com.mat.familytracker.utils.MySharedPreferences;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

public class AllMapsActivity extends AppCompatActivity implements GoogleMap.OnPoiClickListener {

    private GoogleMap mGooglemap;
    private static final int ANIMATE_SPEEED_TURN = 1000;
    private static final int BEARING_OFFSET = 20;
    List<FamilyMemberModel> familyMemberModelList;
    HashMap<Marker, LocationDetailsModel> usersMarkersInfo;
    private Handler handler = new Handler(Looper.getMainLooper());
    private Runnable runnable = new Runnable() {
        @Override
        public void run() {
            refreshMap();
            // wrap this in IF statement to make a way of stopping the looping.
//            handler.postDelayed(this, Constants.FASTEST_INTERVAL_OF_TRACKING);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_all_maps);
        setupActionBar();
        initializeMap(null);

        findViewById(R.id.refreshMap).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                refreshMap();
                AestheticDialog.showToaster(AllMapsActivity.this, null, "Showing all members Locations on map", AestheticDialog.INFO);
            }
        });
        if (getIntent().getSerializableExtra(Constants.FAMILY_MEM_MODEL) != null) {
            FamilyMemberModel familyMemberModel = (FamilyMemberModel) getIntent().getSerializableExtra(Constants.FAMILY_MEM_MODEL);
            showFamilyMemberMap(familyMemberModel, true);
            setTitle(familyMemberModel.getName());
        } else {
            getFamilyList();
        }
        ArrayList<FamilyMemberModel> myList = (ArrayList<FamilyMemberModel>) getIntent().getSerializableExtra(Constants.FAMILY_MEMBER_LIST);
        RecyclerView listView = findViewById(R.id.map_list_members);
        listView.setLayoutManager(new LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false));
        BaseRecyclerListener listener = new BaseRecyclerListener() {
            @Override
            public void onItemClicked(Object selectedObj, int postion) {
                if (selectedObj != null) {
                    showFamilyMemberMap((FamilyMemberModel) selectedObj, true);
                    setTitle(((FamilyMemberModel) selectedObj).getName());
                }
            }

            @Override
            public void onItemLongPressed(Object selectedObj, int postion) {

            }
        };
        MapFamilyMemberListAdapter familyListAdapter = new MapFamilyMemberListAdapter(this, listener, myList);
        listView.setAdapter(familyListAdapter);
        startTimer();
    }

    private void getFamilyList() {
        // getFamilyName using familyname from database
        final String familyName = MySharedPreferences.getInstance().getFamilyName(this);
        if (familyName == null) {
            return;
        }
        CommonUtils.getInstance().showProgressDialog(this);
        FirebaseHandler.getInstance().getFamilyMembersList(familyName, new CommonListener() {
            @Override
            public void onTaskCompleted(Object value) {
                if (value != null) {
                    familyMemberModelList = (ArrayList<FamilyMemberModel>) value;
                    initializeMap(familyMemberModelList);
                }
                CommonUtils.getInstance().closeProgressDialog();

            }
        });

    }

    private void initializeMap(final List<FamilyMemberModel> familyMemberModelList) {
        usersMarkersInfo = new HashMap<>();

        ((MapFragment) getFragmentManager().findFragmentById(R.id.all_map_activity)).getMapAsync(new OnMapReadyCallback() {
            @Override
            public void onMapReady(final GoogleMap googleMap) {
                mGooglemap = googleMap;
                if (ContextCompat.checkSelfPermission(AllMapsActivity.this,
                        Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED) {
                    if (mGooglemap != null) {
                        mGooglemap.setMyLocationEnabled(true);
                    }
                    mGooglemap.setOnMyLocationButtonClickListener(new GoogleMap.OnMyLocationButtonClickListener() {
                        @Override
                        public boolean onMyLocationButtonClick() {
                            GPSHandler.getInstance().getCurrentLocation(AllMapsActivity.this, new GPSTrackerListener() {
                                @Override
                                public void onLocationFetched(Location location) {
                                    Toast.makeText(AllMapsActivity.this, "moving to your current location", Toast.LENGTH_SHORT).show();
                                    moveCameraPosition(location.getLatitude(), location.getLongitude(), mGooglemap);
                                }
                            });
                            return false;
                        }
                    });
                }
                googleMap.setOnPoiClickListener(AllMapsActivity.this);
                googleMap.getUiSettings().setZoomControlsEnabled(true);
                googleMap.setMinZoomPreference(5);
                googleMap.setMaxZoomPreference(100);
                if (familyMemberModelList != null && !familyMemberModelList.isEmpty()) {

                    for (final FamilyMemberModel familyMemberModel : familyMemberModelList) {
                        if (familyMemberModel != null && familyMemberModel.getMemberId() != null) {
                            showFamilyMemberMap(familyMemberModel, false);
                        }

                    }
                }
                MapCustomInfoAdapter customInfoWindowAdapter = new MapCustomInfoAdapter(AllMapsActivity.this, usersMarkersInfo);
                mGooglemap.setInfoWindowAdapter((customInfoWindowAdapter));
//                            userMarker.showInfoWindow();
//        if (userMarker.isInfoWindowShown()) {
//            userMarker.hideInfoWindow();
//        }
                mGooglemap.setOnInfoWindowClickListener(new GoogleMap.OnInfoWindowClickListener() {
                    @Override
                    public void onInfoWindowClick(final Marker marker) {
                        LatLng location = marker.getPosition();
                        GPSHandler.getInstance().getAddressFromLocation(AllMapsActivity.this, location.latitude, location.longitude, new CommonListener() {
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
                });

            }
        });

    }

    private void showFamilyMemberMap(final FamilyMemberModel familyMemberModel, final boolean clearMap) {

        final IconGenerator iconFactory = new IconGenerator(AllMapsActivity.this);
        FirebaseHandler.getInstance().getLocationDetailsOfUserOnce(familyMemberModel.getMobile(), new CommonListener() {
            @Override
            public void onTaskCompleted(Object locationData) {
                if (clearMap) {
                    mGooglemap.clear();
                }
                Marker endMarker;
                LocationDetailsModel locationDetailsModel = (LocationDetailsModel) locationData;
                if (locationDetailsModel != null) {
                    LatLng location = new LatLng(locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude());

                    MarkerOptions marker = new MarkerOptions().
                            icon(BitmapDescriptorFactory.fromBitmap(iconFactory.makeIcon(familyMemberModel.getName()))).
                            position(location).
                            anchor(iconFactory.getAnchorU(), iconFactory.getAnchorV());
                    iconFactory.setBackground(getResources().getDrawable(R.drawable.amu_bubble_mask));
//                                        MarkerOptions marker = new MarkerOptions().position(location).title(familyMemberModel.getName());
//                            userMarker = googleMap.addMarker(marker);
//                            moveCameraPosition(locationDetailsModel.getLatitude(), locationDetailsModel.getLongitude(), googleMap);
//                                        endMarker = googleMap.addMarker(marker);
//                                        endMarker.setTag(familyMemberModel.getMemberId());
//                                        endMarker.setIcon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE));
                    endMarker = addCustomMarker(mGooglemap, location, familyMemberModel);
                    endMarker.setSnippet("click for address..");
                    usersMarkersInfo.put(endMarker, locationDetailsModel);

                    setupCameraPositionForMovement(endMarker.getPosition(), location, endMarker);


                }
            }
        });
    }

    public void drawPolyline(GoogleMap map, LatLng currentPosition, LatLng farEndPosition) {

        PolylineOptions polylineOptions = new PolylineOptions().add(currentPosition).add(farEndPosition).width(5).color(Color.BLACK);
        Polyline mPolyLine = map.addPolyline(polylineOptions);
    }

    public void moveCameraPosition(double latitude, double longitude, GoogleMap googleMap) {
        float zoomLevel = googleMap.getCameraPosition().zoom;
        if (zoomLevel < 14) {
            zoomLevel = 14;
        }
        CameraPosition cameraPosition = new CameraPosition.Builder().target(new LatLng(latitude, longitude)).zoom(zoomLevel).build();
        googleMap.animateCamera(CameraUpdateFactory.newCameraPosition(cameraPosition));
    }

    private void setupActionBar() {
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setDisplayShowHomeEnabled(true);
        }
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

    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.map_type_menu, menu);
        return true;
    }

    @Override
    public boolean onPrepareOptionsMenu(Menu menu) {
        menu.findItem(R.id.location_history).setVisible(false);
        return super.onPrepareOptionsMenu(menu);
    }

    @Override
    public void onPoiClick(PointOfInterest pointOfInterest) {

    }

    private void setupCameraPositionForMovement(final LatLng markerPos, final LatLng secondPos, final Marker userMarker) {

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
//                        MarkerAnimation.animateMarkerToICS(userMarker, secondPos, new LatLngInterpolator.Spherical());
                        drawPolyline(mGooglemap, userMarker.getPosition(), secondPos);
                    }

                    @Override
                    public void onCancel() {
                        System.out.println("cancelling camera");
                    }
                }
        );
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

    private Marker addCustomMarker(GoogleMap mGooglemap, LatLng location, FamilyMemberModel familyMember) {
        Log.d("Cutom marker", "addCustomMarker()");
        // adding a marker on map with image from  drawable
        ImageSaver imageSaver = new ImageSaver(this);
        Bitmap bitmap = imageSaver.loadBitmap(this, familyMember.getMobile());
        String name = CommonUtils.getInstance().getMyName(familyMember);
        if (bitmap != null) {
            return mGooglemap.addMarker(new MarkerOptions()
                    .position(location)
//                    .icon(BitmapDescriptorFactory.fromBitmap(bitmap)));
                    .icon(BitmapDescriptorFactory.fromBitmap(getMarkerBitmapFromView(bitmap, name))));
        } else {
            return mGooglemap.addMarker(new MarkerOptions()
                    .position(location)
                    .icon(BitmapDescriptorFactory.fromBitmap(getMarkerBitmapFromView(R.drawable.blank_profile_picture, name))));
        }
    }

    private void refreshMap() {
        if (mGooglemap != null) {
            mGooglemap.clear();
        }
        if (familyMemberModelList != null) {
            initializeMap(familyMemberModelList);
        } else {
            getFamilyList();
        }
    }

    private void startTimer() {
// post the first runnable, that will start a cascading repeat set of runnables
        handler.postDelayed(runnable, Constants.FASTEST_INTERVAL_OF_TRACKING);
    }

    // create a handler that points to the UI Thread's Looper

    @Override
    protected void onResume() {
        super.onResume();
        if (handler != null && runnable != null) {
            handler.postDelayed(runnable, Constants.FASTEST_INTERVAL_OF_TRACKING);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (handler != null && runnable != null)
            handler.removeCallbacks(runnable);
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (handler != null && runnable != null)
            handler.removeCallbacks(runnable);
    }
}
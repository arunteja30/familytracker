package com.mat.phonesecurity.activity;

import android.app.Dialog;
import android.content.DialogInterface;
import android.os.Bundle;
import android.os.Environment;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.view.ActionMode;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import com.bumptech.glide.Glide;
import com.mat.commonutils.commonutils.CommonUtils;
import com.mat.commonutils.recyclerview.BaseRecyclerListener;
import com.mat.phonesecurity.R;
import com.mat.phonesecurity.adapter.ImagesAdapter;
import com.mat.phonesecurity.model.IntruderModel;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class IntruderPhotosActivity extends AppCompatActivity {
    ImagesAdapter imagesAdapter;
    ActionMode actionMode;
    ActionCallback actionCallback;
    File intruderPhotoDir;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        final List<IntruderModel> intruderModelList = new ArrayList<>();
        setContentView(R.layout.activity_intruder_photos);
        setupActionBar();
        actionCallback = new ActionCallback();
        RecyclerView recyclerView = findViewById(R.id.rv_images);
        recyclerView.setLayoutManager(new LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false));
        intruderPhotoDir = new File(getExternalFilesDir(Environment.DIRECTORY_PICTURES), getResources().getString(R.string.app_name));
        File[] fList = intruderPhotoDir.listFiles();
        //get all the files from a directory
        if (fList != null) {
            for (File file : fList) {
                if (file.isFile()) {
                    intruderModelList.add(new IntruderModel(file.getName(), file.getAbsolutePath()));
                }
            }
            imagesAdapter = new ImagesAdapter(this, new BaseRecyclerListener() {
                @Override
                public void onItemClicked(Object selectedObj, int position) {
                    if (imagesAdapter.selectedItemCount() > 0) {
                        toggleActionBar(position);
                    } else {
                        try {
                            if (selectedObj != null && selectedObj instanceof IntruderModel) {
                                final Dialog fullScreenDialog = CommonUtils.getInstance().showFullScreenDialog(IntruderPhotosActivity.this);
                                fullScreenDialog.setContentView(R.layout.fullscreen_dilaog);
                                ImageView fullImage = fullScreenDialog.findViewById(R.id.iv_full_screen_dialog);
                                Button close = fullScreenDialog.findViewById(R.id.btn_close_full_screen);
                                TextView date = fullScreenDialog.findViewById(R.id.txt_ful_dialog_date);
                                date.setText("Photo captured on " + ((IntruderModel) selectedObj).getDate().replace("SPY_", ""));
                                Glide.with(IntruderPhotosActivity.this).load(((IntruderModel) selectedObj).getImagePath()).into(fullImage);
                                close.setOnClickListener(new View.OnClickListener() {
                                    @Override
                                    public void onClick(View view) {
                                        fullScreenDialog.dismiss();
                                    }
                                });
                                fullScreenDialog.setOnKeyListener(new DialogInterface.OnKeyListener() {
                                    @Override
                                    public boolean onKey(DialogInterface dialogInterface, int keyCode, KeyEvent keyEvent) {
                                        if (keyCode == KeyEvent.KEYCODE_BACK) {
                                            dialogInterface.dismiss();
                                        }
                                        return true;
                                    }
                                });
                                fullScreenDialog.show();
                            }
                        } catch (Exception exception) {
                            exception.printStackTrace();
                        }
                    }
                }

                @Override
                public void onItemLongPressed(Object selectedObj, int postion) {
                    toggleActionBar(postion);
                }
            }, intruderModelList);
            recyclerView.setAdapter(imagesAdapter);
        } else {
            Toast.makeText(this, "No Intruders to Show..", Toast.LENGTH_SHORT).show();
        }
    }

    private void setupActionBar() {
        getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        getSupportActionBar().setDisplayShowHomeEnabled(true);
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
        }
        return super.onOptionsItemSelected(item);
    }
     /*
       toggle selection of items and show the count of selected items on the action bar
     */

    private void toggleSelection(int position) {
        imagesAdapter.toggleSelection(position);
        int count = imagesAdapter.selectedItemCount();
        if (count == 0) {
            actionMode.finish();
        } else {
            actionMode.setTitle(String.valueOf(count));
            actionMode.invalidate();
        }
    }

    /*
       toggling action bar that will change the color and option
     */

    private void toggleActionBar(int position) {
        if (actionMode == null) {
            actionMode = startSupportActionMode(actionCallback);
        }
        toggleSelection(position);
    }

    private class ActionCallback implements ActionMode.Callback {
        @Override
        public boolean onCreateActionMode(ActionMode mode, Menu menu) {
            mode.getMenuInflater().inflate(R.menu.action_menu, menu);
            return true;
        }

        @Override
        public boolean onPrepareActionMode(ActionMode mode, Menu menu) {
            return false;
        }

        @Override
        public boolean onActionItemClicked(ActionMode mode, MenuItem item) {
            if (item.getItemId() == R.id.delteItem) {
                deleteIntruderPhotos();
                mode.finish();
                return true;
            }
            return false;
        }

        @Override
        public void onDestroyActionMode(ActionMode mode) {
            imagesAdapter.clearSelection();
            actionMode = null;

        }
    }

    private void deleteIntruderPhotos() {
        File[] fList = intruderPhotoDir.listFiles();
        List<Integer> selectedItemPositions = imagesAdapter.getSelectedItems();
        for (int i = selectedItemPositions.size() - 1; i >= 0; i--) {
            imagesAdapter.removeItems(selectedItemPositions.get(i));
            if (fList != null && fList[selectedItemPositions.get(i)] != null) {
                fList[selectedItemPositions.get(i)].delete();
            }
        }
        imagesAdapter.notifyDataSetChanged();
    }
}
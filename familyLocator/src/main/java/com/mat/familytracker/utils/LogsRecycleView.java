package com.mat.familytracker.utils;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.TextView;

import com.mat.familytracker.Database.LogsEntity;
import com.mat.familytracker.R;

import java.util.ArrayList;
import java.util.List;

public class LogsRecycleView extends RecyclerView.Adapter<LogsRecycleView.ViewHolder> {

    private List<LogsEntity> mList = new ArrayList<>();
    private LayoutInflater mInflater;
    private OnDeleteClickListener mDeleteListener;

    public void setOnDeleteClickListener(OnDeleteClickListener listener) {
        this.mDeleteListener = listener;
    }

    public LogsRecycleView(Context context) {
        this.mInflater = LayoutInflater.from(context);
    }

    public void removeItem(int position) {
        if (position >= 0 && position < mList.size()) {
            mList.remove(position);
            notifyItemRemoved(position);
            notifyItemRangeChanged(position, mList.size());
        }
    }

    public void add(List<LogsEntity> list) {
        this.mList = list;
        notifyDataSetChanged();
    }

    @Override
    public void onBindViewHolder(@NonNull ViewHolder viewHolder, int i) {
        LogsEntity current = mList.get(i);
        viewHolder.mlatitude.setText("latitude: " + current.getLatitude());
        viewHolder.mlongitude.setText("longitude:" + current.getLongitude());
        viewHolder.date_time.setText("Date Time: " + current.getDateTime());
        viewHolder.location_status.setText("Location Status: " + current.getLocation_Status());
        viewHolder.location_status.setVisibility(View.GONE);
        viewHolder.address.setText("Address: " + current.getAddress());
        viewHolder.link.setText("https://www.google.com/maps/search/?api=1&query=" + current.getLatitude() + "," + current.getLongitude());

        viewHolder.deleteButton.setOnClickListener(v -> {
            if (mDeleteListener != null) {
                mDeleteListener.onDeleteClick(current, i);
            }
        });
    }

    @NonNull
    @Override
    public ViewHolder onCreateViewHolder(@NonNull ViewGroup viewGroup, int i) {
        View view = mInflater.inflate(R.layout.list_item, viewGroup, false);
        return new ViewHolder(view);
    }

    public interface OnDeleteClickListener {
        void onDeleteClick(LogsEntity logsEntity, int position);
    }

    @Override
    public int getItemCount() {
        return mList.size();
    }

    static class ViewHolder extends RecyclerView.ViewHolder {

        private TextView mlatitude, mlongitude, date_time, location_status, address, link;
        private Button deleteButton;

        ViewHolder(View itemView) {
            super(itemView);
            mlatitude = itemView.findViewById(R.id.latitude);
            mlongitude = itemView.findViewById(R.id.longitude);
            date_time = itemView.findViewById(R.id.date_time);
            location_status = itemView.findViewById(R.id.location_status);
            address = itemView.findViewById(R.id.address);
            link = itemView.findViewById(R.id.google_map_link);
            deleteButton = itemView.findViewById(R.id.delete_button);
        }
    }
}

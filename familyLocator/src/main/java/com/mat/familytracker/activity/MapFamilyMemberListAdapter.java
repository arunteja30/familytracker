package com.mat.familytracker.activity;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.appcompat.widget.AppCompatImageView;
import androidx.recyclerview.widget.RecyclerView;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import com.bumptech.glide.Glide;
import com.mat.commonutils.commonutils.CircleTransform;
import com.mat.commonutils.commonutils.ImageSaver;
import com.mat.commonutils.recyclerview.BaseRecyclerListener;
import com.mat.commonutils.recyclerview.BaseViewHolder;
import com.mat.commonutils.recyclerview.GenericRecyclerViewAdapter;
import com.mat.familytracker.R;
import com.mat.familytracker.domain.FamilyMemberModel;

import java.util.List;

public class MapFamilyMemberListAdapter extends GenericRecyclerViewAdapter {
    BaseRecyclerListener mListener;
    Context activity;
    List<FamilyMemberModel> modelList;
    private int selectedIndex = -1;
    private ImageSaver fileUtils;

    public MapFamilyMemberListAdapter(Context context, BaseRecyclerListener listener, List items) {
        super(context, listener, items);
        this.activity = context;
        this.mListener = listener;
        this.modelList = items;
        this.fileUtils = new ImageSaver(activity);
    }

    @Override
    public BaseViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        LayoutInflater layoutInflater = LayoutInflater.from(parent.getContext());
        View listItem = layoutInflater.inflate(R.layout.family_member_map, parent, false);
        ViewHolder viewHolder = new ViewHolder(listItem);
        return viewHolder;
    }


    @Override
    public void onBindViewHolder(@NonNull RecyclerView.ViewHolder viewHolder, int position) {
        ViewHolder holder = (ViewHolder) viewHolder;
        final FamilyMemberModel item = modelList.get(position);
        final int viewPos = position;
        if (item != null) {
            if (selectedIndex == position) selectedIndex = -1;
            holder.name.setText(item.getName());
            Glide.with(activity).load(fileUtils.getFilePath(activity, item.getMobile()))
                    .transform(new CircleTransform(activity)).placeholder(R.drawable.blank_profile_picture)
                    .fallback(R.drawable.blank_profile_picture).into(holder.profilePic);

            holder.itemView.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    mListener.onItemClicked(item, viewPos);
                }
            });
        }
    }

    public class ViewHolder extends BaseViewHolder {
        TextView name;
        AppCompatImageView profilePic;

        public ViewHolder(View view) {
            super(view);
            name = (TextView) view.findViewById(R.id.map_family_mbr_list_name);
            profilePic = view.findViewById(R.id.map_family_mbr_list_profilepic);
        }

        @Override
        public void onBind(Object item) {

        }

    }
}

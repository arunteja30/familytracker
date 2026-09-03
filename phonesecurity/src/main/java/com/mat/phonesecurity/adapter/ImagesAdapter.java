package com.mat.phonesecurity.adapter;

import android.content.Context;
import android.graphics.Color;
import android.util.SparseBooleanArray;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;

import com.bumptech.glide.Glide;
import com.mat.commonutils.recyclerview.GenericRecyclerViewAdapter;
import com.mat.commonutils.recyclerview.BaseRecyclerListener;
import com.mat.commonutils.recyclerview.BaseViewHolder;
import com.mat.phonesecurity.model.IntruderModel;
import com.mat.phonesecurity.R;

import java.util.ArrayList;
import java.util.List;

public class ImagesAdapter extends GenericRecyclerViewAdapter {
    BaseRecyclerListener mListener;
    Context activity;
    private SparseBooleanArray selectedItems;
    private int selectedIndex = -1;
    List<IntruderModel> modelList;

    public ImagesAdapter(Context context, BaseRecyclerListener listener, List items) {
        super(context, listener, items);
        this.activity = context;
        this.mListener = listener;
        this.modelList = items;
        selectedItems = new SparseBooleanArray();
    }

    @Override
    public BaseViewHolder onCreateViewHolder(ViewGroup parent, int viewType) {
        LayoutInflater layoutInflater = LayoutInflater.from(parent.getContext());
        View listItem = layoutInflater.inflate(R.layout.image_item, parent, false);
        ViewHolder viewHolder = new ViewHolder(listItem);
        return viewHolder;

    }


    /*
       This method helps you to get all selected items from the list
     */

    public List<Integer> getSelectedItems() {
        List<Integer> items = new ArrayList<>(selectedItems.size());
        for (int i = 0; i < selectedItems.size(); i++) {
            items.add(selectedItems.keyAt(i));
        }
        return items;
    }

    /*
       this will be used when we want to delete items from our list
     */
    public void removeItems(int position) {
        modelList.remove(position);
        selectedIndex = -1;

    }

    /*
       for clearing our selection
     */

    public void clearSelection() {
        selectedItems.clear();
        notifyDataSetChanged();
    }

    /*
             this function will toggle the selection of items
     */

    public void toggleSelection(int position) {
        selectedIndex = position;
        if (selectedItems.get(position, false)) {
            selectedItems.delete(position);
        } else {
            selectedItems.put(position, true);
        }
        notifyItemChanged(position);
    }

    /*
      How many items have been selected? this method exactly the same . this will return a total number of selected items.
     */

    public int selectedItemCount() {
        return selectedItems.size();
    }

    @Override
    public int getItemCount() {
        return modelList.size();
    }

    /*
      This method will trigger when we we long press the item and it will change the icon of the item to check icon.
    */
    private void toggleIcon(View view, int position) {
        if (selectedItems.get(position, false)) {
            view.setBackgroundColor(Color.BLUE);
            if (selectedIndex == position) selectedIndex = -1;
        } else {
            view.setBackgroundColor(Color.WHITE);
            if (selectedIndex == position) selectedIndex = -1;
        }
    }

    @Override
    public void onBindViewHolder(BaseViewHolder viewHolder, final int position) {
        ViewHolder holder = (ViewHolder) viewHolder;
        IntruderModel item = modelList.get(position);
        final int viewPos = position;
        if (item != null) {
            if (selectedIndex == position) selectedIndex = -1;
            final IntruderModel userModel = (IntruderModel) item;
            holder.name.setText("Captured On : " + userModel.getDate().replace("SPY_", ""));
            Glide.with(activity).load(userModel.getImagePath()).into(holder.intruderImage);
            holder.intruderImage.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    mListener.onItemClicked(userModel, viewPos);
                }
            });
            holder.intruderImage.setOnLongClickListener(new View.OnLongClickListener() {
                @Override
                public boolean onLongClick(View view) {
                    mListener.onItemLongPressed(userModel, viewPos);
                    return true;
                }
            });
            toggleIcon(holder.itemView, position);
        }
    }

    public class ViewHolder extends BaseViewHolder {
        TextView name;
        ImageView intruderImage;

        public ViewHolder(View itemView) {
            super(itemView);
            this.name = (TextView) itemView.findViewById(R.id.txt_date);
            this.intruderImage = (ImageView) itemView.findViewById(R.id.iv_intruder_image);

        }

        @Override
        public void onBind(Object item) {

        }

    }

}

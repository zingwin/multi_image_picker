package com.sangcomz.fishbun.util;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.AsyncTask;
import android.provider.MediaStore;

import androidx.annotation.NonNull;

import com.sangcomz.fishbun.MimeType;
import com.sangcomz.fishbun.bean.Media;
import com.sangcomz.fishbun.ext.MimeTypeExt;

import java.util.ArrayList;
import java.util.List;

public class DisplayImage extends AsyncTask<Void, Void, List<Media>> {
    public interface DisplayImageListener {
        void OnDisplayImageDidSelectFinish(List<Media> medias);
    }
    private Long bucketId;
    private ContentResolver resolver;
    private List<MimeType> exceptMimeType;
    private List<String> specifyFolderList;
    private DisplayImageListener listener;
    private int pageSize = -1;
    private int pageNum = -1;

    public void setPageNum(int pageNum) {
        this.pageNum = pageNum;
    }

    public void setPageSize(int pageSize) {
        this.pageSize = pageSize;
    }

    public DisplayImage(Long bucketId, List<MimeType> exceptMimeType, List<String> specifyFolderList, Context context) {
        this.bucketId = bucketId;
        this.exceptMimeType = exceptMimeType;
        this.specifyFolderList = specifyFolderList;
        this.resolver = context.getContentResolver();
    }

    public void setListener(DisplayImageListener listener) {
        this.listener = listener;
    }

    @Override
    protected List<Media> doInBackground(Void... params) {
        return getAllMediaThumbnailsPath(bucketId, exceptMimeType, specifyFolderList);
    }

    @Override
    protected void onPostExecute(List<Media> result) {
        super.onPostExecute(result);
        if (listener != null) {
            listener.OnDisplayImageDidSelectFinish(result);
        }
    }

    @NonNull
    private List<Media> getAllMediaThumbnailsPath(long id, List<MimeType> exceptMimeTypeList, List<String> specifyFolderList) {
        String bucketId = String.valueOf(id);
        String sort = MediaStore.Files.FileColumns._ID + " DESC ";
        if (pageNum > 0 && pageSize > 0) {
            sort = sort + " LIMIT " + pageSize + " OFFSET " + (pageNum - 1) * pageSize;
        }

        Uri images = MediaStore.Files.getContentUri("external");
        String selection = MediaStore.Files.FileColumns.MEDIA_TYPE + "="
                + MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
                + " OR "
                + MediaStore.Files.FileColumns.MEDIA_TYPE + "="
                + MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO;
        Cursor c;
        if ("0".equals(bucketId)) {
            c = resolver.query(images, null, selection, null, sort);
        }else {
            selection = "(" + selection + ") AND " + MediaStore.MediaColumns.BUCKET_ID + " = ?";
            String[] selectionArgs = {bucketId};
            c = resolver.query(images, null, selection, selectionArgs, sort);
        }
        ArrayList<Media> medias = new ArrayList<>();
        if (c != null) {
            try {
                if (c.moveToFirst()) {
                    do {
                        Media media = new Media();
                        String mimeType = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.MIME_TYPE));
                        String buckName = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME));
                        if (isExceptMemeType(exceptMimeTypeList, mimeType) || isNotContainsSpecifyFolderList(specifyFolderList, buckName)) continue;
                        String originPath = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.DATA));
                        String originName = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME));
                        String originWidth = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.WIDTH));
                        String originHeight = c.getString(c.getColumnIndex(MediaStore.Files.FileColumns.HEIGHT));
                        String duration = c.getString(c.getColumnIndex(MediaStore.Video.Media.DURATION));
                        String imgId = c.getString(c.getColumnIndex(MediaStore.MediaColumns._ID));
                        String identifier = "";
                        if (mimeType.startsWith("image")) {
                            identifier = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, imgId).toString();
                            media.setFileType("image");
                        }else if (mimeType.startsWith("video")) {
                            identifier = Uri.withAppendedPath(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, imgId).toString();
                            media.setFileType("video");
                        }else {
                            identifier = Uri.withAppendedPath(MediaStore.Files.getContentUri("external"), imgId).toString();
                            media.setFileType("file");
                        }
                        media.setBucketId(bucketId);
                        media.setBucketName(buckName);
                        media.setOriginName(originName);
                        media.setOriginHeight(originHeight);
                        media.setOriginWidth(originWidth);
                        media.setOriginPath(originPath);
                        media.setDuration(duration);
                        media.setIdentifier(identifier);
                        media.setMimeType(mimeType);
                        media.setMediaId(imgId);
                        medias.add(media);
                    } while (c.moveToNext());
                }
                c.close();
            } catch (Exception e) {
                if (!c.isClosed()) c.close();
            }
        }
        return medias;
    }

    private boolean isExceptMemeType(List<MimeType> mimeTypes, String mimeType){
        for (MimeType type : mimeTypes) {
            if (MimeTypeExt.equalsMimeType(type, mimeType))
                return true;
        }
        return false;
    }

    private boolean isNotContainsSpecifyFolderList(List<String> specifyFolderList, String displayBundleName) {
        if (specifyFolderList.isEmpty()) return false;
        return !specifyFolderList.contains(displayBundleName);
    }
}
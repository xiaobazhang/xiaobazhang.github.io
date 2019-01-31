---
layout: post
title: leveldb源码系列-leveldb中WriteBatch写操作
category: LevelDB
tags: LevelDb
date: 2019-01-30
author: suli
---

* content
{:toc}

## leveldb写过程

leveldb在写操作的时候首先会将数据写到log文件中，同时每次写之前也不会直接写入，leveldb会将写操作作为一个批量操作，最后统一一次性写入日志文件中。其中会涉及到一个leveldb的一个写批量操作的类WriteBatch，该类会将所有操作打包成一个批处理统一会写到文件中。











### 1. WriteBatch类


```c++
class LEVELDB_EXPORT WriteBatch {
 public:
  WriteBatch();
  ~WriteBatch();

  // Store the mapping "key->value" in the database.
  void Put(const Slice& key, const Slice& value);

  // If the database contains a mapping for "key", erase it.  Else do nothing.
  void Delete(const Slice& key);

  // Clear all updates buffered in this batch.
  void Clear();

  // The size of the database changes caused by this batch.
  //
  // This number is tied to implementation details, and may change across
  // releases. It is intended for LevelDB usage metrics.
  size_t ApproximateSize();

  // Support for iterating over the contents of a batch.
  class Handler {
   public:
    virtual ~Handler();
    virtual void Put(const Slice& key, const Slice& value) = 0;
    virtual void Delete(const Slice& key) = 0;
  };
  Status Iterate(Handler* handler) const;

 private:
  friend class WriteBatchInternal;

  std::string rep_;  // See comment in write_batch.cc for the format of rep_

  // Intentionally copyable
};
```
其中WriteBatch中除了put和delete方法外，Handler类是对memtable的操作类，WriteBatchInternal类主要包括对批量写入的时候进行操作进行编码的一个辅助类。

```
class WriteBatchInternal {
 public:
  // Return the number of entries in the batch.
  static int Count(const WriteBatch* batch);

  // Set the count for the number of entries in the batch.
  static void SetCount(WriteBatch* batch, int n);

  // Return the sequence number for the start of this batch.
  static SequenceNumber Sequence(const WriteBatch* batch);

  // Store the specified number as the sequence number for the start of
  // this batch.
  static void SetSequence(WriteBatch* batch, SequenceNumber seq);

  static Slice Contents(const WriteBatch* batch) {
    return Slice(batch->rep_);
  }

  static size_t ByteSize(const WriteBatch* batch) {
    return batch->rep_.size();
  }

  static void SetContents(WriteBatch* batch, const Slice& contents);

  static Status InsertInto(const WriteBatch* batch, MemTable* memtable);

  static void Append(WriteBatch* dst, const WriteBatch* src);
};
```
- 写入前操作

```c++
void WriteBatch::Put(const Slice& key, const Slice& value) {
  WriteBatchInternal::SetCount(this, WriteBatchInternal::Count(this) + 1);
  rep_.push_back(static_cast<char>(kTypeValue));
  PutLengthPrefixedSlice(&rep_, key);
  PutLengthPrefixedSlice(&rep_, value);
}
```
首先第一步将插入的条数记录到rep_变量中，从第9个字节到第12个字节来记录批量插入的个数。然后再记录数据类型，最后对key和value进行编码，最后写到统一的格式中。

- 写入操作


```c++
Status DBImpl::Write(const WriteOptions& options, WriteBatch* my_batch) {
/*struct DBImpl::Writer {
*  WriteBatch* batch;
*  bool sync;
*  bool done;
* port::CondVar cv;
*};
*Writer封装WriteBatch，主要是多了信号量cv用于多线程的同步，以及该batch是否完成的标志done
*/
  Writer w(&mutex_);
  w.batch = my_batch;
  w.sync = options.sync;
  w.done = false;

//加锁,因为w要插入全局队列writers_中
  MutexLock l(&mutex_);
  writers_.push_back(&w);
//只有当w是位于队列头部且w并没有完成时才不用等待
  while (!w.done && &w != writers_.front()) {
    w.cv.Wait();
  }
  //可能该w中的batch被其他线程通过下面讲到的合并操作一起完成了
  if (w.done) {
    return w.status;
  }

  // May temporarily unlock and wait.
  Status status = MakeRoomForWrite(my_batch == NULL);
  uint64_t last_sequence = versions_->LastSequence();
  Writer* last_writer = &w;
  if (status.ok() && my_batch != NULL) {  
  //合并队列中的各个batch到一个新batch中
    WriteBatch* updates = BuildBatchGroup(&last_writer);
  //为合并后的新batch中的第一个操作赋上全局序列号
    WriteBatchInternal::SetSequence(updates, last_sequence + 1);
  //并计算新的全局序列号
    last_sequence += WriteBatchInternal::Count(updates);

    {
    //往磁盘写日志文件开销很大，此时可以释放锁来提高并发，此时其他线程可以将
    //新的writer插入到队列writers_中
      mutex_.Unlock();
    //将batch中的每条操作写入日志文件log_中
      status = log_->AddRecord(WriteBatchInternal::Contents(updates));
      bool sync_error = false;
      if (status.ok() && options.sync) {
      //是否要求立马刷盘将log写到磁盘，因为我们知道文件系统还有自己的缓存
        status = logfile_->Sync();
        if (!status.ok()) {
          sync_error = true;
        }
      }
      if (status.ok()) {
       //将batch中每条操作插入到memtable中
        status = WriteBatchInternal::InsertInto(updates, mem_);
      }
      //重新加锁
      mutex_.Lock();
    }
    //因为updates已经写入了log和memtable，可以清空了
    if (updates == tmp_batch_) tmp_batch_->Clear();
    //重新设置新的全局序列号
    versions_->SetLastSequence(last_sequence);
  }

  while (true) {
  //因为我们的updates可能合并了writers_队列中的很多,当前线程完成了其他线程的
  //writer，只需唤醒这些已完成writer的线程
    Writer* ready = writers_.front();
  //从队列头部取出已完成的writer
    writers_.pop_front();
    if (ready != &w) {
   //如果取出的writer不是当前线程的自己的，则唤醒writer所属的线程，唤醒的线程会执
   //行 if (w.done) {
   // return w.status;
  //}逻辑
      ready->status = status;
      ready->done = true;
      ready->cv.Signal();
    }
    //ready == last_writer说明这已经是合并的batch中最后一个已完成的writer了
    if (ready == last_writer) break;
  }

  // Notify new head of write queue
  if (!writers_.empty()) {
  //队列不空，则唤醒队列头部writer所属的线程，参见上面 while (!w.done && &w != writers_.front())
    writers_.front()->cv.Signal();
  }

  return status;
}
```
最后写入的时候形成的写入数据格式:

![image](https://blog-1256080294.cos.ap-shanghai.myqcloud.com/leveldb.png?q-sign-algorithm=sha1&q-ak=AKIDfMGjrNqoCEyJlGnuUG4UByY2JroS6MSR&q-sign-time=1548941403;1548943203&q-key-time=1548941403;1548943203&q-header-list=&q-url-param-list=&q-signature=729e1603448525cccae16f6587e7dd3573be3404&x-cos-security-token=db0737bc4be82032e04772e9c00fccd128645c9710001)

leveldb通过对数据的打包整体写入log内，提高了io吞吐率，写入速度飞快。

## 参考

leveldb: https://github.com/google/leveldb.git

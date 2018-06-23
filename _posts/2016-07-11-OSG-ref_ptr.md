---
layout: post
title: OSG三维渲染引擎--学习ref_ptr智能指针原理和设计
category: 技术
tags: OSG
keywords: 
description: 
---

## 前言
最近一直帮助导师开发一个三维渲染小项目，不太复杂，工作量也不太大。但是由于我一年多以前深入研究过OSG这个渲染引擎，并且基于OSG开发过中科院一个较大的项目。时光穿梭让我又接触到这个技术了，同时在学校还有最后的两个月，所以趁这个时间好好研究一下整体OSG框架。同时希望将我以前对于大面积场景渲染的分层分片显示技术进行重新的开发进而打包进入OSG源码中。

# OSG中ref_ptr智能指针原理和设计
在大规模渲染场景中，场景之间是以树形节点进行组织的，节点数目会非常多，依靠程序开发去手动释放资源几乎不可能。所以需要自动进行资源的释放。和Java中内存管理近似，OSG中使用了基于引用计数的方法来管理内存。其中智能指针的使用如下代码所示：

	osg::ref_ptr<osg::Node> node = new osg::Node;
创建对象后即可使用，不需要对node进行释放。ref_ptr类代码存放于osg/ref_ptr.cpp文件中。代码如下所示：

	template<class T> 
	class ref_ptr
	{
    public:
        typedef T element_type;
	
        ref_ptr() : _ptr(0) {}//初始化ref_ptr中对象指针变量
        ref_ptr(T* ptr) : _ptr(ptr) { if (_ptr) _ptr->ref(); }//在创建对象时，引用计数加1
        ref_ptr(const ref_ptr& rp) : _ptr(rp._ptr) { if (_ptr) _ptr->ref(); }
        template<class Other> ref_ptr(const ref_ptr<Other>& rp) : _ptr(rp._ptr) { if (_ptr) _ptr->ref(); }
        ref_ptr(observer_ptr<T>& optr) : _ptr(0) { optr.lock(*this); }
		//当局部变量ref_ptr调用析构函数的时候应用计数减1
        ~ref_ptr() { if (_ptr) _ptr->unref();  _ptr = 0; }

        ref_ptr& operator = (const ref_ptr& rp)
        {
            assign(rp);
            return *this;
        }

        template<class Other> ref_ptr& operator = (const ref_ptr<Other>& rp)
        {
            assign(rp);
            return *this;
        }
		
        inline ref_ptr& operator = (T* ptr)
        {
            if (_ptr==ptr) return *this;
            T* tmp_ptr = _ptr;
            _ptr = ptr;
            if (_ptr) _ptr->ref();
      
            if (tmp_ptr) tmp_ptr->unref();
            return *this;
        }
	//下面是智能指针的判断操作实现
	#ifdef OSG_USE_REF_PTR_IMPLICIT_OUTPUT_CONVERSION
        operator T*() const { return _ptr; }
	#else
        bool operator == (const ref_ptr& rp) const { return (_ptr==rp._ptr); }
        bool operator == (const T* ptr) const { return (_ptr==ptr); }
        friend bool operator == (const T* ptr, const ref_ptr& rp) { return (ptr==rp._ptr); }

        bool operator != (const ref_ptr& rp) const { return (_ptr!=rp._ptr); }
        bool operator != (const T* ptr) const { return (_ptr!=ptr); }
        friend bool operator != (const T* ptr, const ref_ptr& rp) { return (ptr!=rp._ptr); }
 
        bool operator < (const ref_ptr& rp) const { return (_ptr<rp._ptr); }
    private:
        typedef T* ref_ptr::*unspecified_bool_type;

    public:
        operator unspecified_bool_type() const { return valid()? &ref_ptr::_ptr : 0; }
	#endif
        T& operator*() const { return *_ptr; }//解操作
        T* operator->() const { return _ptr; }//指针
        T* get() const { return _ptr; }//获取对象指针
        bool operator!() const   { return _ptr==0; } // not required
        bool valid() const       { return _ptr!=0; }//判断对象指针是否非空
	//release用于返回对象指针，引用计数不变
        T* release() { T* tmp=_ptr; if (_ptr) _ptr->unref_nodelete(); _ptr=0; return tmp; }
        void swap(ref_ptr& rp) { T* tmp=_ptr; _ptr=rp._ptr; rp._ptr=tmp; }
    private:
        template<class Other> void assign(const ref_ptr<Other>& rp)
        {
            if (_ptr==rp._ptr) return;
            T* tmp_ptr = _ptr;
            _ptr = rp._ptr;
            if (_ptr) _ptr->ref();
       
            if (tmp_ptr) tmp_ptr->unref();
        }

        template<class Other> friend class ref_ptr;

        T* _ptr;//记录对象指针
	};

OSG的大部分类都是派生于Referenced基类。该基类实现了引用计数中的ref()和unref()函数，这两个函数分别是操作Referenced基类中的引用计数值。在Referenced.cpp中定义了这两个函数的实现。

	inline int Referenced::ref() const
	{
	    if (_refMutex)//如果存在锁
	    {	
			//在对引用变量操作是加上区域锁
	        OpenThreads::ScopedLock<OpenThreads::Mutex> lock(*_refMutex); 
	        return ++_refCount;//引用变量加1
	    }
	    else
	    {
	        return ++_refCount;
	    }
	}
	
	inline int Referenced::unref() const
	{
	    int newRef;
	    bool needDelete = false;
	    if (_refMutex)
	    {
	        OpenThreads::ScopedLock<OpenThreads::Mutex> lock(*_refMutex); 
	        newRef = --_refCount;
	        needDelete = newRef==0;
	    }
	    else
	    {
	        newRef = --_refCount;
	        needDelete = newRef==0;
	    }
	
	    if (needDelete)
	    {
	        signalObserversAndDelete(true,true);//释放对象内存
	    }
	    return newRef;
	}

可以看到Referenced基类中保存了派生于该类的对象的引用计数。ref_ptr基于模板实现，可以针对类型无关。本文借鉴OSG中智能指针的原理，自己写了一个智能指针原型。

	#include <iostream>
	#include <string>
	
	using namespace std;
	class Base 
	{
	public:
		Base(){}
		~Base(){}
		int add()
		{
			return ++_count;	
		}
		int unadd()
		{
			int tmpCount = --_count;
			if(tmpCount == 0)
				{ 
				std::cout<<"delete now"<<std::endl;
				std::cout<<"this = "<<(int*)(this)<<std::endl;
				delete this;
			}
			return tmpCount;
		}
		int getCount()
			{
			return _count;
		}
	
	private:
		int _count;//引用计数
	
	};
	
	class Machine: public Base
	{
		public:
			Machine(){}
			~Machine(){}
			void Move()
				{
				std::cout<<"I'm Move"<<std::endl;
			}
			void Work()
				{
				std::cout<<"I'm Work"<<std::endl;
			}	
	};
	
	template<class T>
	class auto_ptr
	{
		public:
			auto_ptr():_ptr(0){}
			auto_ptr(T* ptr)
			{
				_ptr = ptr;
				if(_ptr)
					{
					_ptr->add();
				}
			}
			auto_ptr(const auto_ptr& ptr)
				{
				_ptr = ptr._ptr;
				if(_ptr)
					{
					_ptr->add();
				}
			}
			auto_ptr& operator = (const auto_ptr& ptr)
				{
				if(_ptr == ptr._ptr)
					return *this;
				T* tmpptr = _ptr;
				_ptr = ptr._ptr;
				if(_ptr)
					_ptr->add();
				if(tmpptr)
					tmpptr->unadd();
				return *this;
			}
			auto_ptr& operator = (T* ptr)
				{
				if(_ptr == ptr)
					return *this;
				T* tmpptr = _ptr;
				_ptr = ptr->_ptr;
				if(_ptr)
					_ptr->add();
				if(tmpptr)
					tmpptr->unadd();
				return *this;	
			}
			T& operator*() const
				{
				return *_ptr;
			}
			T* operator->() const
				{
				return _ptr;
			}
			bool operator!() const 
				{
				return _ptr == 0;
			}
		~auto_ptr() 
			{
			if(_ptr)
				{
				_ptr->unadd();
				_ptr = 0;
			}
		}
		private:
			T* _ptr;
	};

	int main(void) 
	{ 
		auto_ptr<Machine> machine1 = new Machine();
		std::cout<<"machine1 = "<<machine1->getCount()<<std::endl;
		auto_ptr<Machine> machine2 = new Machine();
		std::cout<<"machine2 = "<<machine2->getCount()<<std::endl;
		machine2 = machine1;
		std::cout<<"machine2 = "<<machine2->getCount()<<std::endl;
		return 0;
	}

运行结果如下图所示：

![1](http://p06g9mpb2.bkt.clouddn.com/18-6-23/68458609.jpg)

上式实现了一个智能指针的原型，基于模板实现。基于模板有很大的好处，可以实现与类型无关。OSG中只能指针实现很完整，对多线程的考虑很完善，同时在对类的拷贝上做了更加细致的处理。
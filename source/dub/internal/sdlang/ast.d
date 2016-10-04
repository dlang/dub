// SDLang-D
// Written in the D programming language.

module dub.internal.sdlang.ast;

version (Have_sdlang_d) public import sdlang.ast;
else:

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.string;

import dub.internal.sdlang.exception;
import dub.internal.sdlang.token;
import dub.internal.sdlang.util;

class Attribute
{
	Value    value;
	Location location;
	
	private Tag _parent;
	/// Get parent tag. To set a parent, attach this Attribute to its intended
	/// parent tag by calling `Tag.add(...)`, or by passing it to
	/// the parent tag's constructor.
	@property Tag parent()
	{
		return _parent;
	}

	private string _namespace;
	/++
	This tag's namespace. Empty string if no namespace.
	
	Note that setting this value is O(n) because internal lookup structures 
	need to be updated.
	
	Note also, that setting this may change where this tag is ordered among
	its parent's list of tags.
	+/
	@property string namespace()
	{
		return _namespace;
	}
	///ditto
	@property void namespace(string value)
	{
		if(_parent && _namespace != value)
		{
			// Remove
			auto saveParent = _parent;
			if(_parent)
				this.remove();

			// Change namespace
			_namespace = value;

			// Re-add
			if(saveParent)
				saveParent.add(this);
		}
		else
			_namespace = value;
	}
	
	private string _name;
	/++
	This attribute's name, not including namespace.
	
	Use `getFullName().toString` if you want the namespace included.
	
	Note that setting this value is O(n) because internal lookup structures 
	need to be updated.

	Note also, that setting this may change where this attribute is ordered
	among its parent's list of tags.
	+/
	@property string name()
	{
		return _name;
	}
	///ditto
	@property void name(string value)
	{
		if(_parent && _name != value)
		{
			_parent.updateId++;
			
			void removeFromGroupedLookup(string ns)
			{
				// Remove from _parent._attributes[ns]
				auto sameNameAttrs = _parent._attributes[ns][_name];
				auto targetIndex = sameNameAttrs.countUntil(this);
				_parent._attributes[ns][_name].removeIndex(targetIndex);
			}
			
			// Remove from _parent._tags
			removeFromGroupedLookup(_namespace);
			removeFromGroupedLookup("*");

			// Change name
			_name = value;
			
			// Add to new locations in _parent._attributes
			_parent._attributes[_namespace][_name] ~= this;
			_parent._attributes["*"][_name] ~= this;
		}
		else
			_name = value;
	}

	/// This tag's name, including namespace if one exists.
	deprecated("Use 'getFullName().toString()'")
	@property string fullName()
	{
		return getFullName().toString();
	}
	
	/// This tag's name, including namespace if one exists.
	FullName getFullName()
	{
		return FullName(_namespace, _name);
	}

	this(string namespace, string name, Value value, Location location = Location(0, 0, 0))
	{
		this._namespace = namespace;
		this._name      = name;
		this.location   = location;
		this.value      = value;
	}
	
	this(string name, Value value, Location location = Location(0, 0, 0))
	{
		this._namespace = "";
		this._name      = name;
		this.location   = location;
		this.value      = value;
	}
	
	/// Copy this Attribute.
	/// The clone does $(B $(I not)) have a parent, even if the original does.
	Attribute clone()
	{
		return new Attribute(_namespace, _name, value, location);
	}
	
	/// Removes `this` from its parent, if any. Returns `this` for chaining.
	/// Inefficient ATM, but it works.
	Attribute remove()
	{
		if(!_parent)
			return this;
		
		void removeFromGroupedLookup(string ns)
		{
			// Remove from _parent._attributes[ns]
			auto sameNameAttrs = _parent._attributes[ns][_name];
			auto targetIndex = sameNameAttrs.countUntil(this);
			_parent._attributes[ns][_name].removeIndex(targetIndex);
		}
		
		// Remove from _parent._attributes
		removeFromGroupedLookup(_namespace);
		removeFromGroupedLookup("*");

		// Remove from _parent.allAttributes
		auto allAttrsIndex = _parent.allAttributes.countUntil(this);
		_parent.allAttributes.removeIndex(allAttrsIndex);

		// Remove from _parent.attributeIndicies
		auto sameNamespaceAttrs = _parent.attributeIndicies[_namespace];
		auto attrIndiciesIndex = sameNamespaceAttrs.countUntil(allAttrsIndex);
		_parent.attributeIndicies[_namespace].removeIndex(attrIndiciesIndex);
		
		// Fixup other indicies
		foreach(ns, ref nsAttrIndicies; _parent.attributeIndicies)
		foreach(k, ref v; nsAttrIndicies)
		if(v > allAttrsIndex)
			v--;
		
		_parent.removeNamespaceIfEmpty(_namespace);
		_parent.updateId++;
		_parent = null;
		return this;
	}

	override bool opEquals(Object o)
	{
		auto a = cast(Attribute)o;
		if(!a)
			return false;

		return
			_namespace == a._namespace &&
			_name      == a._name      &&
			value      == a.value;
	}
	
	string toSDLString()()
	{
		Appender!string sink;
		this.toSDLString(sink);
		return sink.data;
	}

	void toSDLString(Sink)(ref Sink sink) if(isOutputRange!(Sink,char))
	{
		if(_namespace != "")
		{
			sink.put(_namespace);
			sink.put(':');
		}

		sink.put(_name);
		sink.put('=');
		value.toSDLString(sink);
	}
}

/// Deep-copy an array of Tag or Attribute.
/// The top-level clones are $(B $(I not)) attached to any parent, even if the originals are.
T[] clone(T)(T[] arr) if(is(T==Tag) || is(T==Attribute))
{
	T[] newArr;
	newArr.length = arr.length;
	
	foreach(i; 0..arr.length)
		newArr[i] = arr[i].clone();
	
	return newArr;
}

class Tag
{
	/// File/Line/Column/Index information for where this tag was located in
	/// its original SDLang file.
	Location location;
	
	/// Access all this tag's values, as an array of type `sdlang.token.Value`.
	Value[]  values;

	private Tag _parent;
	/// Get parent tag. To set a parent, attach this Tag to its intended
	/// parent tag by calling `Tag.add(...)`, or by passing it to
	/// the parent tag's constructor.
	@property Tag parent()
	{
		return _parent;
	}

	private string _namespace;
	/++
	This tag's namespace. Empty string if no namespace.
	
	Note that setting this value is O(n) because internal lookup structures 
	need to be updated.
	
	Note also, that setting this may change where this tag is ordered among
	its parent's list of tags.
	+/
	@property string namespace()
	{
		return _namespace;
	}
	///ditto
	@property void namespace(string value)
	{
		//TODO: Can we do this in-place, without removing/adding and thus
		//      modyfying the internal order?
		if(_parent && _namespace != value)
		{
			// Remove
			auto saveParent = _parent;
			if(_parent)
				this.remove();

			// Change namespace
			_namespace = value;

			// Re-add
			if(saveParent)
				saveParent.add(this);
		}
		else
			_namespace = value;
	}
	
	private string _name;
	/++
	This tag's name, not including namespace.
	
	Use `getFullName().toString` if you want the namespace included.
	
	Note that setting this value is O(n) because internal lookup structures 
	need to be updated.

	Note also, that setting this may change where this tag is ordered among
	its parent's list of tags.
	+/
	@property string name()
	{
		return _name;
	}
	///ditto
	@property void name(string value)
	{
		//TODO: Seriously? Can't we at least do the "*" modification *in-place*?
		
		if(_parent && _name != value)
		{
			_parent.updateId++;
			
			// Not the most efficient, but it works.
			void removeFromGroupedLookup(string ns)
			{
				// Remove from _parent._tags[ns]
				auto sameNameTags = _parent._tags[ns][_name];
				auto targetIndex = sameNameTags.countUntil(this);
				_parent._tags[ns][_name].removeIndex(targetIndex);
			}
			
			// Remove from _parent._tags
			removeFromGroupedLookup(_namespace);
			removeFromGroupedLookup("*");
			
			// Change name
			_name = value;
			
			// Add to new locations in _parent._tags
			//TODO: Can we re-insert while preserving the original order?
			_parent._tags[_namespace][_name] ~= this;
			_parent._tags["*"][_name] ~= this;
		}
		else
			_name = value;
	}
	
	/// This tag's name, including namespace if one exists.
	deprecated("Use 'getFullName().toString()'")
	@property string fullName()
	{
		return getFullName().toString();
	}
	
	/// This tag's name, including namespace if one exists.
	FullName getFullName()
	{
		return FullName(_namespace, _name);
	}
	
	// Tracks dirtiness. This is incremented every time a change is made which
	// could invalidate existing ranges. This way, the ranges can detect when
	// they've been invalidated.
	private size_t updateId=0;
	
	this(Tag parent = null)
	{
		if(parent)
			parent.add(this);
	}

	this(
		string namespace, string name,
		Value[] values=null, Attribute[] attributes=null, Tag[] children=null
	)
	{
		this(null, namespace, name, values, attributes, children);
	}

	this(
		Tag parent, string namespace, string name,
		Value[] values=null, Attribute[] attributes=null, Tag[] children=null
	)
	{
		this._namespace = namespace;
		this._name      = name;

		if(parent)
			parent.add(this);
		
		this.values = values;
		this.add(attributes);
		this.add(children);
	}

	/// Deep-copy this Tag.
	/// The clone does $(B $(I not)) have a parent, even if the original does.
	Tag clone()
	{
		auto newTag = new Tag(_namespace, _name, values.dup, allAttributes.clone(), allTags.clone());
		newTag.location = location;
		return newTag;
	}
	
	private Attribute[] allAttributes; // In same order as specified in SDL file.
	private Tag[]       allTags;       // In same order as specified in SDL file.
	private string[]    allNamespaces; // In same order as specified in SDL file.

	private size_t[][string] attributeIndicies; // allAttributes[ attributes[namespace][i] ]
	private size_t[][string] tagIndicies;       // allTags[ tags[namespace][i] ]

	private Attribute[][string][string] _attributes; // attributes[namespace or "*"][name][i]
	private Tag[][string][string]       _tags;       // tags[namespace or "*"][name][i]
	
	/// Adds a Value, Attribute, Tag (or array of such) as a member/child of this Tag.
	/// Returns `this` for chaining.
	/// Throws `ValidationException` if trying to add an Attribute or Tag
	/// that already has a parent.
	Tag add(Value val)
	{
		values ~= val;
		updateId++;
		return this;
	}
	
	///ditto
	Tag add(Value[] vals)
	{
		foreach(val; vals)
			add(val);

		return this;
	}
	
	///ditto
	Tag add(Attribute attr)
	{
		if(attr._parent)
		{
			throw new ValidationException(
				"Attribute is already attached to a parent tag. "~
				"Use Attribute.remove() before adding it to another tag."
			);
		}
		
		if(!allNamespaces.canFind(attr._namespace))
			allNamespaces ~= attr._namespace;

		attr._parent = this;
		
		allAttributes ~= attr;
		attributeIndicies[attr._namespace] ~= allAttributes.length-1;
		_attributes[attr._namespace][attr._name] ~= attr;
		_attributes["*"]            [attr._name] ~= attr;

		updateId++;
		return this;
	}
	
	///ditto
	Tag add(Attribute[] attrs)
	{
		foreach(attr; attrs)
			add(attr);

		return this;
	}
	
	///ditto
	Tag add(Tag tag)
	{
		if(tag._parent)
		{
			throw new ValidationException(
				"Tag is already attached to a parent tag. "~
				"Use Tag.remove() before adding it to another tag."
			);
		}

		if(!allNamespaces.canFind(tag._namespace))
			allNamespaces ~= tag._namespace;
		
		tag._parent = this;

		allTags ~= tag;
		tagIndicies[tag._namespace] ~= allTags.length-1;
		_tags[tag._namespace][tag._name] ~= tag;
		_tags["*"]           [tag._name] ~= tag;
		
		updateId++;
		return this;
	}
	
	///ditto
	Tag add(Tag[] tags)
	{
		foreach(tag; tags)
			add(tag);

		return this;
	}
	
	/// Removes `this` from its parent, if any. Returns `this` for chaining.
	/// Inefficient ATM, but it works.
	Tag remove()
	{
		if(!_parent)
			return this;
		
		void removeFromGroupedLookup(string ns)
		{
			// Remove from _parent._tags[ns]
			auto sameNameTags = _parent._tags[ns][_name];
			auto targetIndex = sameNameTags.countUntil(this);
			_parent._tags[ns][_name].removeIndex(targetIndex);
		}
		
		// Remove from _parent._tags
		removeFromGroupedLookup(_namespace);
		removeFromGroupedLookup("*");

		// Remove from _parent.allTags
		auto allTagsIndex = _parent.allTags.countUntil(this);
		_parent.allTags.removeIndex(allTagsIndex);

		// Remove from _parent.tagIndicies
		auto sameNamespaceTags = _parent.tagIndicies[_namespace];
		auto tagIndiciesIndex = sameNamespaceTags.countUntil(allTagsIndex);
		_parent.tagIndicies[_namespace].removeIndex(tagIndiciesIndex);
		
		// Fixup other indicies
		foreach(ns, ref nsTagIndicies; _parent.tagIndicies)
		foreach(k, ref v; nsTagIndicies)
		if(v > allTagsIndex)
			v--;
		
		_parent.removeNamespaceIfEmpty(_namespace);
		_parent.updateId++;
		_parent = null;
		return this;
	}
	
	private void removeNamespaceIfEmpty(string namespace)
	{
		// If namespace has no attributes, remove it from attributeIndicies/_attributes
		if(namespace in attributeIndicies && attributeIndicies[namespace].length == 0)
		{
			attributeIndicies.remove(namespace);
			_attributes.remove(namespace);
		}

		// If namespace has no tags, remove it from tagIndicies/_tags
		if(namespace in tagIndicies && tagIndicies[namespace].length == 0)
		{
			tagIndicies.remove(namespace);
			_tags.remove(namespace);
		}
		
		// If namespace is now empty, remove it from allNamespaces
		if(
			namespace !in tagIndicies &&
			namespace !in attributeIndicies
		)
		{
			auto allNamespacesIndex = allNamespaces.length - allNamespaces.find(namespace).length;
			allNamespaces = allNamespaces[0..allNamespacesIndex] ~ allNamespaces[allNamespacesIndex+1..$];
		}
	}
	
	struct NamedMemberRange(T, string membersGrouped)
	{
		private Tag tag;
		private string namespace; // "*" indicates "all namespaces" (ok since it's not a valid namespace name)
		private string name;
		private size_t updateId;  // Tag's updateId when this range was created.

		this(Tag tag, string namespace, string name, size_t updateId)
		{
			this.tag       = tag;
			this.namespace = namespace;
			this.name      = name;
			this.updateId  = updateId;
			frontIndex = 0;

			if(
				tag !is null &&
				namespace in mixin("tag."~membersGrouped) &&
				name in mixin("tag."~membersGrouped~"[namespace]")
			)
				endIndex = mixin("tag."~membersGrouped~"[namespace][name].length");
			else
				endIndex = 0;
		}
		
		invariant()
		{
			assert(
				this.updateId == tag.updateId,
				"This range has been invalidated by a change to the tag."
			);
		}

		@property bool empty()
		{
			return tag is null || frontIndex == endIndex;
		}
		
		private size_t frontIndex;
		@property T front()
		{
			return this[0];
		}
		void popFront()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			frontIndex++;
		}

		private size_t endIndex; // One past the last element
		@property T back()
		{
			return this[$-1];
		}
		void popBack()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			endIndex--;
		}
		
		alias length opDollar;
		@property size_t length()
		{
			return endIndex - frontIndex;
		}
		
		@property typeof(this) save()
		{
			auto r = typeof(this)(this.tag, this.namespace, this.name, this.updateId);
			r.frontIndex = this.frontIndex;
			r.endIndex   = this.endIndex;
			return r;
		}
		
		typeof(this) opSlice()
		{
			return save();
		}
		
		typeof(this) opSlice(size_t start, size_t end)
		{
			auto r = save();
			r.frontIndex = this.frontIndex + start;
			r.endIndex   = this.frontIndex + end;
			
			if(
				r.frontIndex > this.endIndex ||
				r.endIndex > this.endIndex ||
				r.frontIndex > r.endIndex
			)
				throw new DOMRangeException(tag, "Slice out of range");
			
			return r;
		}

		T opIndex(size_t index)
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			return mixin("tag."~membersGrouped~"[namespace][name][frontIndex+index]");
		}
	}

	struct MemberRange(T, string allMembers, string memberIndicies, string membersGrouped)
	{
		private Tag tag;
		private string namespace; // "*" indicates "all namespaces" (ok since it's not a valid namespace name)
		private bool isMaybe;
		private size_t updateId;  // Tag's updateId when this range was created.
		private size_t initialEndIndex;

		this(Tag tag, string namespace, bool isMaybe)
		{
			this.tag       = tag;
			this.namespace = namespace;
			this.updateId  = tag.updateId;
			this.isMaybe   = isMaybe;
			frontIndex = 0;

			if(tag is null)
				endIndex = 0;
			else
			{

				if(namespace == "*")
					initialEndIndex = mixin("tag."~allMembers~".length");
				else if(namespace in mixin("tag."~memberIndicies))
					initialEndIndex = mixin("tag."~memberIndicies~"[namespace].length");
				else
					initialEndIndex = 0;
			
				endIndex = initialEndIndex;
			}
		}
		
		invariant()
		{
			assert(
				this.updateId == tag.updateId,
				"This range has been invalidated by a change to the tag."
			);
		}

		@property bool empty()
		{
			return tag is null || frontIndex == endIndex;
		}
		
		private size_t frontIndex;
		@property T front()
		{
			return this[0];
		}
		void popFront()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			frontIndex++;
		}

		private size_t endIndex; // One past the last element
		@property T back()
		{
			return this[$-1];
		}
		void popBack()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			endIndex--;
		}
		
		alias length opDollar;
		@property size_t length()
		{
			return endIndex - frontIndex;
		}
		
		@property typeof(this) save()
		{
			auto r = typeof(this)(this.tag, this.namespace, this.isMaybe);
			r.frontIndex      = this.frontIndex;
			r.endIndex        = this.endIndex;
			r.initialEndIndex = this.initialEndIndex;
			r.updateId        = this.updateId;
			return r;
		}
		
		typeof(this) opSlice()
		{
			return save();
		}
		
		typeof(this) opSlice(size_t start, size_t end)
		{
			auto r = save();
			r.frontIndex = this.frontIndex + start;
			r.endIndex   = this.frontIndex + end;
			
			if(
				r.frontIndex > this.endIndex ||
				r.endIndex > this.endIndex ||
				r.frontIndex > r.endIndex
			)
				throw new DOMRangeException(tag, "Slice out of range");
			
			return r;
		}
		
		T opIndex(size_t index)
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			if(namespace == "*")
				return mixin("tag."~allMembers~"[ frontIndex+index ]");
			else
				return mixin("tag."~allMembers~"[ tag."~memberIndicies~"[namespace][frontIndex+index] ]");
		}
		
		alias NamedMemberRange!(T,membersGrouped) ThisNamedMemberRange;
		ThisNamedMemberRange opIndex(string name)
		{
			if(frontIndex != 0 || endIndex != initialEndIndex)
			{
				throw new DOMRangeException(tag,
					"Cannot lookup tags/attributes by name on a subset of a range, "~
					"only across the entire tag. "~
					"Please make sure you haven't called popFront or popBack on this "~
					"range and that you aren't using a slice of the range."
				);
			}
			
			if(!isMaybe && empty)
				throw new DOMRangeException(tag, "Range is empty");
			
			if(!isMaybe && name !in this)
				throw new DOMRangeException(tag, `No such `~T.stringof~` named: "`~name~`"`);

			return ThisNamedMemberRange(tag, namespace, name, updateId);
		}

		bool opBinaryRight(string op)(string name) if(op=="in")
		{
			if(frontIndex != 0 || endIndex != initialEndIndex)
			{
				throw new DOMRangeException(tag,
					"Cannot lookup tags/attributes by name on a subset of a range, "~
					"only across the entire tag. "~
					"Please make sure you haven't called popFront or popBack on this "~
					"range and that you aren't using a slice of the range."
				);
			}
			
			if(tag is null)
				return false;
			
			return
				namespace in mixin("tag."~membersGrouped) &&
				name in mixin("tag."~membersGrouped~"[namespace]") && 
				mixin("tag."~membersGrouped~"[namespace][name].length") > 0;
		}
	}

	struct NamespaceRange
	{
		private Tag tag;
		private bool isMaybe;
		private size_t updateId;  // Tag's updateId when this range was created.

		this(Tag tag, bool isMaybe)
		{
			this.tag      = tag;
			this.isMaybe  = isMaybe;
			this.updateId = tag.updateId;
			frontIndex = 0;
			endIndex = tag.allNamespaces.length;
		}

		invariant()
		{
			assert(
				this.updateId == tag.updateId,
				"This range has been invalidated by a change to the tag."
			);
		}
		
		@property bool empty()
		{
			return frontIndex == endIndex;
		}
		
		private size_t frontIndex;
		@property NamespaceAccess front()
		{
			return this[0];
		}
		void popFront()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");
			
			frontIndex++;
		}

		private size_t endIndex; // One past the last element
		@property NamespaceAccess back()
		{
			return this[$-1];
		}
		void popBack()
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");
			
			endIndex--;
		}
		
		alias length opDollar;
		@property size_t length()
		{
			return endIndex - frontIndex;
		}
		
		@property NamespaceRange save()
		{
			auto r = NamespaceRange(this.tag, this.isMaybe);
			r.frontIndex = this.frontIndex;
			r.endIndex   = this.endIndex;
			r.updateId   = this.updateId;
			return r;
		}
		
		typeof(this) opSlice()
		{
			return save();
		}
		
		typeof(this) opSlice(size_t start, size_t end)
		{
			auto r = save();
			r.frontIndex = this.frontIndex + start;
			r.endIndex   = this.frontIndex + end;
			
			if(
				r.frontIndex > this.endIndex ||
				r.endIndex > this.endIndex ||
				r.frontIndex > r.endIndex
			)
				throw new DOMRangeException(tag, "Slice out of range");
			
			return r;
		}
		
		NamespaceAccess opIndex(size_t index)
		{
			if(empty)
				throw new DOMRangeException(tag, "Range is empty");

			auto namespace = tag.allNamespaces[frontIndex+index];
			return NamespaceAccess(
				namespace,
				AttributeRange(tag, namespace, isMaybe),
				TagRange(tag, namespace, isMaybe)
			);
		}
		
		NamespaceAccess opIndex(string namespace)
		{
			if(!isMaybe && empty)
				throw new DOMRangeException(tag, "Range is empty");
			
			if(!isMaybe && namespace !in this)
				throw new DOMRangeException(tag, `No such namespace: "`~namespace~`"`);
			
			return NamespaceAccess(
				namespace,
				AttributeRange(tag, namespace, isMaybe),
				TagRange(tag, namespace, isMaybe)
			);
		}
		
		/// Inefficient when range is a slice or has used popFront/popBack, but it works.
		bool opBinaryRight(string op)(string namespace) if(op=="in")
		{
			if(frontIndex == 0 && endIndex == tag.allNamespaces.length)
			{
				return
					namespace in tag.attributeIndicies ||
					namespace in tag.tagIndicies;
			}
			else
				// Slower fallback method
				return tag.allNamespaces[frontIndex..endIndex].canFind(namespace);
		}
	}

	static struct NamespaceAccess
	{
		string name;
		AttributeRange attributes;
		TagRange tags;
	}

	alias MemberRange!(Attribute, "allAttributes", "attributeIndicies", "_attributes") AttributeRange;
	alias MemberRange!(Tag,       "allTags",       "tagIndicies",       "_tags"      ) TagRange;
	static assert(isRandomAccessRange!AttributeRange);
	static assert(isRandomAccessRange!TagRange);
	static assert(isRandomAccessRange!NamespaceRange);

	/++
	Access all attributes that don't have a namespace

	Returns a random access range of `Attribute` objects that supports
	numeric-indexing, string-indexing, slicing and length.
	
	Since SDLang allows multiple attributes with the same name,
	string-indexing returns a random access range of all attributes
	with the given name.
	
	The string-indexing does $(B $(I not)) support namespace prefixes.
	Use `namespace[string]`.`attributes` or `all`.`attributes` for that.
	
	See $(LINK2 https://github.com/Abscissa/SDLang-D/blob/master/HOWTO.md#tag-and-attribute-api-summary, API Overview)
	for a high-level overview (and examples) of how to use this.
	+/
	@property AttributeRange attributes()
	{
		return AttributeRange(this, "", false);
	}

	/++
	Access all direct-child tags that don't have a namespace.
	
	Returns a random access range of `Tag` objects that supports
	numeric-indexing, string-indexing, slicing and length.
	
	Since SDLang allows multiple tags with the same name, string-indexing
	returns a random access range of all immediate child tags with the
	given name.
	
	The string-indexing does $(B $(I not)) support namespace prefixes.
	Use `namespace[string]`.`attributes` or `all`.`attributes` for that.
	
	See $(LINK2 https://github.com/Abscissa/SDLang-D/blob/master/HOWTO.md#tag-and-attribute-api-summary, API Overview)
	for a high-level overview (and examples) of how to use this.
	+/
	@property TagRange tags()
	{
		return TagRange(this, "", false);
	}
	
	/++
	Access all namespaces in this tag, and the attributes/tags within them.
	
	Returns a random access range of `NamespaceAccess` elements that supports
	numeric-indexing, string-indexing, slicing and length.
	
	See $(LINK2 https://github.com/Abscissa/SDLang-D/blob/master/HOWTO.md#tag-and-attribute-api-summary, API Overview)
	for a high-level overview (and examples) of how to use this.
	+/
	@property NamespaceRange namespaces()
	{
		return NamespaceRange(this, false);
	}

	/// Access all attributes and tags regardless of namespace.
	///
	/// See $(LINK2 https://github.com/Abscissa/SDLang-D/blob/master/HOWTO.md#tag-and-attribute-api-summary, API Overview)
	/// for a better understanding (and examples) of how to use this.
	@property NamespaceAccess all()
	{
		// "*" isn't a valid namespace name, so we can use it to indicate "all namespaces"
		return NamespaceAccess(
			"*",
			AttributeRange(this, "*", false),
			TagRange(this, "*", false)
		);
	}

	struct MaybeAccess
	{
		Tag tag;

		/// Access all attributes that don't have a namespace
		@property AttributeRange attributes()
		{
			return AttributeRange(tag, "", true);
		}

		/// Access all direct-child tags that don't have a namespace
		@property TagRange tags()
		{
			return TagRange(tag, "", true);
		}
		
		/// Access all namespaces in this tag, and the attributes/tags within them.
		@property NamespaceRange namespaces()
		{
			return NamespaceRange(tag, true);
		}

		/// Access all attributes and tags regardless of namespace.
		@property NamespaceAccess all()
		{
			// "*" isn't a valid namespace name, so we can use it to indicate "all namespaces"
			return NamespaceAccess(
				"*",
				AttributeRange(tag, "*", true),
				TagRange(tag, "*", true)
			);
		}
	}
	
	/// Access `attributes`, `tags`, `namespaces` and `all` like normal,
	/// except that looking up a non-existant name/namespace with
	/// opIndex(string) results in an empty array instead of
	/// a thrown `sdlang.exception.DOMRangeException`.
	///
	/// See $(LINK2 https://github.com/Abscissa/SDLang-D/blob/master/HOWTO.md#tag-and-attribute-api-summary, API Overview)
	/// for a more information (and examples) of how to use this.
	@property MaybeAccess maybe()
	{
		return MaybeAccess(this);
	}
	
	// Internal implementations for the get/expect functions further below:
	
	private Tag getTagImpl(FullName tagFullName, Tag defaultValue=null, bool useDefaultValue=true)
	{
		auto tagNS   = tagFullName.namespace;
		auto tagName = tagFullName.name;
		
		// Can find namespace?
		if(tagNS !in _tags)
		{
			if(useDefaultValue)
				return defaultValue;
			else
				throw new TagNotFoundException(this, tagFullName, "No tags found in namespace '"~namespace~"'");
		}

		// Can find tag in namespace?
		if(tagName !in _tags[tagNS] || _tags[tagNS][tagName].length == 0)
		{
			if(useDefaultValue)
				return defaultValue;
			else
				throw new TagNotFoundException(this, tagFullName, "Can't find tag '"~tagFullName.toString()~"'");
		}

		// Return last matching tag found
		return _tags[tagNS][tagName][$-1];
	}

	private T getValueImpl(T)(T defaultValue, bool useDefaultValue=true)
	if(isValueType!T)
	{
		// Find value
		foreach(value; this.values)
		{
			if(value.type == typeid(T))
				return value.get!T();
		}
		
		// No value of type T found
		if(useDefaultValue)
			return defaultValue;
		else
		{
			throw new ValueNotFoundException(
				this,
				FullName(this.namespace, this.name),
				typeid(T),
				"No value of type "~T.stringof~" found."
			);
		}
	}

	private T getAttributeImpl(T)(FullName attrFullName, T defaultValue, bool useDefaultValue=true)
	if(isValueType!T)
	{
		auto attrNS   = attrFullName.namespace;
		auto attrName = attrFullName.name;
		
		// Can find namespace and attribute name?
		if(attrNS !in this._attributes || attrName !in this._attributes[attrNS])
		{
			if(useDefaultValue)
				return defaultValue;
			else
			{
				throw new AttributeNotFoundException(
					this, this.getFullName(), attrFullName, typeid(T),
					"Can't find attribute '"~FullName.combine(attrNS, attrName)~"'"
				);
			}
		}

		// Find value with chosen type
		foreach(attr; this._attributes[attrNS][attrName])
		{
			if(attr.value.type == typeid(T))
				return attr.value.get!T();
		}
		
		// Chosen type not found
		if(useDefaultValue)
			return defaultValue;
		else
		{
			throw new AttributeNotFoundException(
				this, this.getFullName(), attrFullName, typeid(T),
				"Can't find attribute '"~FullName.combine(attrNS, attrName)~"' of type "~T.stringof
			);
		}
	}

	// High-level interfaces for get/expect funtions:
	
	/++
	Lookup a child tag by name. Returns null if not found.
	
	Useful if you only expect one, and only one, child tag of a given name.
	Only looks for immediate child tags of `this`, doesn't search recursively.
	
	If you expect multiple tags by the same name and want to get them all,
	use `maybe`.`tags[string]` instead.
	
	The name can optionally include a namespace, as in `"namespace:name"`.
	Or, you can search all namespaces using `"*:name"`. Use an empty string
	to search for anonymous tags, or `"namespace:"` for anonymous tags inside
	a namespace. Wildcard searching is only supported for namespaces, not names.
	Use `maybe`.`tags[0]` if you don't care about the name.
	
	If there are multiple tags by the chosen name, the $(B $(I last tag)) will
	always be chosen. That is, this function considers later tags with the
	same name to override previous ones.
	
	If the tag cannot be found, and you provides a default value, the default
	value is returned. Otherwise null is returned. If you'd prefer an
	exception thrown, use `expectTag` instead.
	+/
	Tag getTag(string fullTagName, Tag defaultValue=null)
	{
		auto parsedName = FullName.parse(fullTagName);
		parsedName.ensureNoWildcardName(
			"Instead, use 'Tag.maybe.tags[0]', 'Tag.maybe.all.tags[0]' or 'Tag.maybe.namespace[ns].tags[0]'."
		);
		return getTagImpl(parsedName, defaultValue);
	}
	
	///
	@("Tag.getTag")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1
			foo 2  // getTag considers this to override the first foo

			ns1:foo 3
			ns1:foo 4   // getTag considers this to override the first ns1:foo
			ns2:foo 33
			ns2:foo 44  // getTag considers this to override the first ns2:foo
		`);
		assert( root.getTag("foo"    ).values[0].get!int() == 2  );
		assert( root.getTag("ns1:foo").values[0].get!int() == 4  );
		assert( root.getTag("*:foo"  ).values[0].get!int() == 44 ); // Search all namespaces
		
		// Not found
		// If you'd prefer an exception, use `expectTag` instead.
		assert( root.getTag("doesnt-exist") is null );

		// Default value
		auto foo = root.getTag("foo");
		assert( root.getTag("doesnt-exist", foo) is foo );
	}
	
	/++
	Lookup a child tag by name. Throws if not found.
	
	Useful if you only expect one, and only one, child tag of a given name.
	Only looks for immediate child tags of `this`, doesn't search recursively.
	
	If you expect multiple tags by the same name and want to get them all,
	use `tags[string]` instead.

	The name can optionally include a namespace, as in `"namespace:name"`.
	Or, you can search all namespaces using `"*:name"`. Use an empty string
	to search for anonymous tags, or `"namespace:"` for anonymous tags inside
	a namespace. Wildcard searching is only supported for namespaces, not names.
	Use `tags[0]` if you don't care about the name.
	
	If there are multiple tags by the chosen name, the $(B $(I last tag)) will
	always be chosen. That is, this function considers later tags with the
	same name to override previous ones.
	
	If no such tag is found, an `sdlang.exception.TagNotFoundException` will
	be thrown. If you'd rather receive a default value, use `getTag` instead.
	+/
	Tag expectTag(string fullTagName)
	{
		auto parsedName = FullName.parse(fullTagName);
		parsedName.ensureNoWildcardName(
			"Instead, use 'Tag.tags[0]', 'Tag.all.tags[0]' or 'Tag.namespace[ns].tags[0]'."
		);
		return getTagImpl(parsedName, null, false);
	}
	
	///
	@("Tag.expectTag")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1
			foo 2  // expectTag considers this to override the first foo

			ns1:foo 3
			ns1:foo 4   // expectTag considers this to override the first ns1:foo
			ns2:foo 33
			ns2:foo 44  // expectTag considers this to override the first ns2:foo
		`);
		assert( root.expectTag("foo"    ).values[0].get!int() == 2  );
		assert( root.expectTag("ns1:foo").values[0].get!int() == 4  );
		assert( root.expectTag("*:foo"  ).values[0].get!int() == 44 ); // Search all namespaces
		
		// Not found
		// If you'd rather receive a default value than an exception, use `getTag` instead.
		assertThrown!TagNotFoundException( root.expectTag("doesnt-exist") );
	}
	
	/++
	Retrieve a value of type T from `this` tag. Returns a default value if not found.
	
	Useful if you only expect one value of type T from this tag. Only looks for
	values of `this` tag, it does not search child tags. If you wish to search
	for a value in a child tag (for example, if this current tag is a root tag),
	try `getTagValue`.

	If you want to get more than one value from this tag, use `values` instead.

	If this tag has multiple values, the $(B $(I first)) value matching the
	requested type will be returned. Ie, Extra values in the tag are ignored.
	
	You may provide a default value to be returned in case no value of
	the requested type can be found. If you don't provide a default value,
	`T.init` will be used.
	
	If you'd rather an exception be thrown when a value cannot be found,
	use `expectValue` instead.
	+/
	T getValue(T)(T defaultValue = T.init) if(isValueType!T)
	{
		return getValueImpl!T(defaultValue, true);
	}

	///
	@("Tag.getValue")
	unittest
	{
		import std.exception;
		import std.math;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 true 2 false
		`);
		auto foo = root.getTag("foo");
		assert( foo.getValue!int() == 1 );
		assert( foo.getValue!bool() == true );

		// Value found, default value ignored.
		assert( foo.getValue!int(999) == 1 );

		// No strings found
		// If you'd prefer an exception, use `expectValue` instead.
		assert( foo.getValue!string("Default") == "Default" );
		assert( foo.getValue!string() is null );

		// No floats found
		assert( foo.getValue!float(99.9).approxEqual(99.9) );
		assert( foo.getValue!float().isNaN() );
	}

	/++
	Retrieve a value of type T from `this` tag. Throws if not found.
	
	Useful if you only expect one value of type T from this tag. Only looks
	for values of `this` tag, it does not search child tags. If you wish to
	search for a value in a child tag (for example, if this current tag is a
	root tag), try `expectTagValue`.

	If you want to get more than one value from this tag, use `values` instead.

	If this tag has multiple values, the $(B $(I first)) value matching the
	requested type will be returned. Ie, Extra values in the tag are ignored.
	
	An `sdlang.exception.ValueNotFoundException` will be thrown if no value of
	the requested type can be found. If you'd rather receive a default value,
	use `getValue` instead.
	+/
	T expectValue(T)() if(isValueType!T)
	{
		return getValueImpl!T(T.init, false);
	}

	///
	@("Tag.expectValue")
	unittest
	{
		import std.exception;
		import std.math;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 true 2 false
		`);
		auto foo = root.getTag("foo");
		assert( foo.expectValue!int() == 1 );
		assert( foo.expectValue!bool() == true );

		// No strings or floats found
		// If you'd rather receive a default value than an exception, use `getValue` instead.
		assertThrown!ValueNotFoundException( foo.expectValue!string() );
		assertThrown!ValueNotFoundException( foo.expectValue!float() );
	}

	/++
	Lookup a child tag by name, and retrieve a value of type T from it.
	Returns a default value if not found.
	
	Useful if you only expect one value of type T from a given tag. Only looks
	for immediate child tags of `this`, doesn't search recursively.

	This is a shortcut for `getTag().getValue()`, except if the tag isn't found,
	then instead of a null reference error, it will return the requested
	`defaultValue` (or T.init by default).
	+/
	T getTagValue(T)(string fullTagName, T defaultValue = T.init) if(isValueType!T)
	{
		auto tag = getTag(fullTagName);
		if(!tag)
			return defaultValue;
		
		return tag.getValue!T(defaultValue);
	}

	///
	@("Tag.getTagValue")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 "a" 2 "b"
			foo 3 "c" 4 "d"  // getTagValue considers this to override the first foo
			
			bar "hi"
			bar 379  // getTagValue considers this to override the first bar
		`);
		assert( root.getTagValue!int("foo") == 3 );
		assert( root.getTagValue!string("foo") == "c" );

		// Value found, default value ignored.
		assert( root.getTagValue!int("foo", 999) == 3 );

		// Tag not found
		// If you'd prefer an exception, use `expectTagValue` instead.
		assert( root.getTagValue!int("doesnt-exist", 999) == 999 );
		assert( root.getTagValue!int("doesnt-exist") == 0 );
		
		// The last "bar" tag doesn't have an int (only the first "bar" tag does)
		assert( root.getTagValue!string("bar", "Default") == "Default" );
		assert( root.getTagValue!string("bar") is null );

		// Using namespaces:
		root = parseSource(`
			ns1:foo 1 "a" 2 "b"
			ns1:foo 3 "c" 4 "d"
			ns2:foo 11 "aa" 22 "bb"
			ns2:foo 33 "cc" 44 "dd"
			
			ns1:bar "hi"
			ns1:bar 379  // getTagValue considers this to override the first bar
		`);
		assert( root.getTagValue!int("ns1:foo") == 3  );
		assert( root.getTagValue!int("*:foo"  ) == 33 ); // Search all namespaces

		assert( root.getTagValue!string("ns1:foo") == "c"  );
		assert( root.getTagValue!string("*:foo"  ) == "cc" ); // Search all namespaces
		
		// The last "bar" tag doesn't have a string (only the first "bar" tag does)
		assert( root.getTagValue!string("*:bar", "Default") == "Default" );
		assert( root.getTagValue!string("*:bar") is null );
	}

	/++
	Lookup a child tag by name, and retrieve a value of type T from it.
	Throws if not found,
	
	Useful if you only expect one value of type T from a given tag. Only
	looks for immediate child tags of `this`, doesn't search recursively.
	
	This is a shortcut for `expectTag().expectValue()`.
	+/
	T expectTagValue(T)(string fullTagName) if(isValueType!T)
	{
		return expectTag(fullTagName).expectValue!T();
	}

	///
	@("Tag.expectTagValue")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 "a" 2 "b"
			foo 3 "c" 4 "d"  // expectTagValue considers this to override the first foo
			
			bar "hi"
			bar 379  // expectTagValue considers this to override the first bar
		`);
		assert( root.expectTagValue!int("foo") == 3 );
		assert( root.expectTagValue!string("foo") == "c" );
		
		// The last "bar" tag doesn't have a string (only the first "bar" tag does)
		// If you'd rather receive a default value than an exception, use `getTagValue` instead.
		assertThrown!ValueNotFoundException( root.expectTagValue!string("bar") );

		// Tag not found
		assertThrown!TagNotFoundException( root.expectTagValue!int("doesnt-exist") );

		// Using namespaces:
		root = parseSource(`
			ns1:foo 1 "a" 2 "b"
			ns1:foo 3 "c" 4 "d"
			ns2:foo 11 "aa" 22 "bb"
			ns2:foo 33 "cc" 44 "dd"
			
			ns1:bar "hi"
			ns1:bar 379  // expectTagValue considers this to override the first bar
		`);
		assert( root.expectTagValue!int("ns1:foo") == 3  );
		assert( root.expectTagValue!int("*:foo"  ) == 33 ); // Search all namespaces

		assert( root.expectTagValue!string("ns1:foo") == "c"  );
		assert( root.expectTagValue!string("*:foo"  ) == "cc" ); // Search all namespaces
		
		// The last "bar" tag doesn't have a string (only the first "bar" tag does)
		assertThrown!ValueNotFoundException( root.expectTagValue!string("*:bar") );
		
		// Namespace not found
		assertThrown!TagNotFoundException( root.expectTagValue!int("doesnt-exist:bar") );
	}

	/++
	Lookup an attribute of `this` tag by name, and retrieve a value of type T
	from it. Returns a default value if not found.
	
	Useful if you only expect one attribute of the given name and type.
	
	Only looks for attributes of `this` tag, it does not search child tags.
	If you wish to search for a value in a child tag (for example, if this
	current tag is a root tag), try `getTagAttribute`.
	
	If you expect multiple attributes by the same name and want to get them all,
	use `maybe`.`attributes[string]` instead.

	The attribute name can optionally include a namespace, as in
	`"namespace:name"`. Or, you can search all namespaces using `"*:name"`.
	(Note that unlike tags. attributes can't be anonymous - that's what
	values are.) Wildcard searching is only supported for namespaces, not names.
	Use `maybe`.`attributes[0]` if you don't care about the name.

	If this tag has multiple attributes, the $(B $(I first)) attribute
	matching the requested name and type will be returned. Ie, Extra
	attributes in the tag are ignored.
	
	You may provide a default value to be returned in case no attribute of
	the requested name and type can be found. If you don't provide a default
	value, `T.init` will be used.
	
	If you'd rather an exception be thrown when an attribute cannot be found,
	use `expectAttribute` instead.
	+/
	T getAttribute(T)(string fullAttributeName, T defaultValue = T.init) if(isValueType!T)
	{
		auto parsedName = FullName.parse(fullAttributeName);
		parsedName.ensureNoWildcardName(
			"Instead, use 'Attribute.maybe.tags[0]', 'Attribute.maybe.all.tags[0]' or 'Attribute.maybe.namespace[ns].tags[0]'."
		);
		return getAttributeImpl!T(parsedName, defaultValue);
	}
	
	///
	@("Tag.getAttribute")
	unittest
	{
		import std.exception;
		import std.math;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo z=0 X=1 X=true X=2 X=false
		`);
		auto foo = root.getTag("foo");
		assert( foo.getAttribute!int("X") == 1 );
		assert( foo.getAttribute!bool("X") == true );

		// Value found, default value ignored.
		assert( foo.getAttribute!int("X", 999) == 1 );

		// Attribute name not found
		// If you'd prefer an exception, use `expectValue` instead.
		assert( foo.getAttribute!int("doesnt-exist", 999) == 999 );
		assert( foo.getAttribute!int("doesnt-exist") == 0 );

		// No strings found
		assert( foo.getAttribute!string("X", "Default") == "Default" );
		assert( foo.getAttribute!string("X") is null );

		// No floats found
		assert( foo.getAttribute!float("X", 99.9).approxEqual(99.9) );
		assert( foo.getAttribute!float("X").isNaN() );

		
		// Using namespaces:
		root = parseSource(`
			foo  ns1:z=0  ns1:X=1  ns1:X=2  ns2:X=3  ns2:X=4
		`);
		foo = root.getTag("foo");
		assert( foo.getAttribute!int("ns2:X") == 3 );
		assert( foo.getAttribute!int("*:X") == 1 ); // Search all namespaces
		
		// Namespace not found
		assert( foo.getAttribute!int("doesnt-exist:X", 999) == 999 );
		
		// No attribute X is in the default namespace
		assert( foo.getAttribute!int("X", 999) == 999 );
		
		// Attribute name not found
		assert( foo.getAttribute!int("ns1:doesnt-exist", 999) == 999 );
	}
	
	/++
	Lookup an attribute of `this` tag by name, and retrieve a value of type T
	from it. Throws if not found.
	
	Useful if you only expect one attribute of the given name and type.
	
	Only looks for attributes of `this` tag, it does not search child tags.
	If you wish to search for a value in a child tag (for example, if this
	current tag is a root tag), try `expectTagAttribute`.

	If you expect multiple attributes by the same name and want to get them all,
	use `attributes[string]` instead.

	The attribute name can optionally include a namespace, as in
	`"namespace:name"`. Or, you can search all namespaces using `"*:name"`.
	(Note that unlike tags. attributes can't be anonymous - that's what
	values are.) Wildcard searching is only supported for namespaces, not names.
	Use `attributes[0]` if you don't care about the name.

	If this tag has multiple attributes, the $(B $(I first)) attribute
	matching the requested name and type will be returned. Ie, Extra
	attributes in the tag are ignored.
	
	An `sdlang.exception.AttributeNotFoundException` will be thrown if no
	value of the requested type can be found. If you'd rather receive a
	default value, use `getAttribute` instead.
	+/
	T expectAttribute(T)(string fullAttributeName) if(isValueType!T)
	{
		auto parsedName = FullName.parse(fullAttributeName);
		parsedName.ensureNoWildcardName(
			"Instead, use 'Attribute.tags[0]', 'Attribute.all.tags[0]' or 'Attribute.namespace[ns].tags[0]'."
		);
		return getAttributeImpl!T(parsedName, T.init, false);
	}
	
	///
	@("Tag.expectAttribute")
	unittest
	{
		import std.exception;
		import std.math;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo z=0 X=1 X=true X=2 X=false
		`);
		auto foo = root.getTag("foo");
		assert( foo.expectAttribute!int("X") == 1 );
		assert( foo.expectAttribute!bool("X") == true );

		// Attribute name not found
		// If you'd rather receive a default value than an exception, use `getAttribute` instead.
		assertThrown!AttributeNotFoundException( foo.expectAttribute!int("doesnt-exist") );

		// No strings found
		assertThrown!AttributeNotFoundException( foo.expectAttribute!string("X") );

		// No floats found
		assertThrown!AttributeNotFoundException( foo.expectAttribute!float("X") );

		
		// Using namespaces:
		root = parseSource(`
			foo  ns1:z=0  ns1:X=1  ns1:X=2  ns2:X=3  ns2:X=4
		`);
		foo = root.getTag("foo");
		assert( foo.expectAttribute!int("ns2:X") == 3 );
		assert( foo.expectAttribute!int("*:X") == 1 ); // Search all namespaces
		
		// Namespace not found
		assertThrown!AttributeNotFoundException( foo.expectAttribute!int("doesnt-exist:X") );
		
		// No attribute X is in the default namespace
		assertThrown!AttributeNotFoundException( foo.expectAttribute!int("X") );
		
		// Attribute name not found
		assertThrown!AttributeNotFoundException( foo.expectAttribute!int("ns1:doesnt-exist") );
	}

	/++
	Lookup a child tag and attribute by name, and retrieve a value of type T
	from it. Returns a default value if not found.
	
	Useful if you only expect one attribute of type T from given
	the tag and attribute names. Only looks for immediate child tags of
	`this`, doesn't search recursively.

	This is a shortcut for `getTag().getAttribute()`, except if the tag isn't
	found, then instead of a null reference error, it will return the requested
	`defaultValue` (or T.init by default).
	+/
	T getTagAttribute(T)(string fullTagName, string fullAttributeName, T defaultValue = T.init) if(isValueType!T)
	{
		auto tag = getTag(fullTagName);
		if(!tag)
			return defaultValue;
		
		return tag.getAttribute!T(fullAttributeName, defaultValue);
	}
	
	///
	@("Tag.getTagAttribute")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo X=1 X="a" X=2 X="b"
			foo X=3 X="c" X=4 X="d"  // getTagAttribute considers this to override the first foo
			
			bar X="hi"
			bar X=379  // getTagAttribute considers this to override the first bar
		`);
		assert( root.getTagAttribute!int("foo", "X") == 3 );
		assert( root.getTagAttribute!string("foo", "X") == "c" );

		// Value found, default value ignored.
		assert( root.getTagAttribute!int("foo", "X", 999) == 3 );

		// Tag not found
		// If you'd prefer an exception, use `expectTagAttribute` instead of `getTagAttribute`
		assert( root.getTagAttribute!int("doesnt-exist", "X", 999)   == 999 );
		assert( root.getTagAttribute!int("doesnt-exist", "X")        == 0   );
		assert( root.getTagAttribute!int("foo", "doesnt-exist", 999) == 999 );
		assert( root.getTagAttribute!int("foo", "doesnt-exist")      == 0   );
		
		// The last "bar" tag doesn't have a string (only the first "bar" tag does)
		assert( root.getTagAttribute!string("bar", "X", "Default") == "Default" );
		assert( root.getTagAttribute!string("bar", "X") is null );
		

		// Using namespaces:
		root = parseSource(`
			ns1:foo X=1 X="a" X=2 X="b"
			ns1:foo X=3 X="c" X=4 X="d"
			ns2:foo X=11 X="aa" X=22 X="bb"
			ns2:foo X=33 X="cc" X=44 X="dd"
			
			ns1:bar attrNS:X="hi"
			ns1:bar attrNS:X=379  // getTagAttribute considers this to override the first bar
		`);
		assert( root.getTagAttribute!int("ns1:foo", "X") == 3  );
		assert( root.getTagAttribute!int("*:foo",   "X") == 33 ); // Search all namespaces

		assert( root.getTagAttribute!string("ns1:foo", "X") == "c"  );
		assert( root.getTagAttribute!string("*:foo",   "X") == "cc" ); // Search all namespaces
		
		// bar's attribute X is't in the default namespace
		assert( root.getTagAttribute!int("*:bar", "X", 999) == 999 );
		assert( root.getTagAttribute!int("*:bar", "X") == 0 );

		// The last "bar" tag's "attrNS:X" attribute doesn't have a string (only the first "bar" tag does)
		assert( root.getTagAttribute!string("*:bar", "attrNS:X", "Default") == "Default" );
		assert( root.getTagAttribute!string("*:bar", "attrNS:X") is null);
	}

	/++
	Lookup a child tag and attribute by name, and retrieve a value of type T
	from it. Throws if not found.
	
	Useful if you only expect one attribute of type T from given
	the tag and attribute names. Only looks for immediate child tags of
	`this`, doesn't search recursively.

	This is a shortcut for `expectTag().expectAttribute()`.
	+/
	T expectTagAttribute(T)(string fullTagName, string fullAttributeName) if(isValueType!T)
	{
		return expectTag(fullTagName).expectAttribute!T(fullAttributeName);
	}
	
	///
	@("Tag.expectTagAttribute")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo X=1 X="a" X=2 X="b"
			foo X=3 X="c" X=4 X="d"  // expectTagAttribute considers this to override the first foo
			
			bar X="hi"
			bar X=379  // expectTagAttribute considers this to override the first bar
		`);
		assert( root.expectTagAttribute!int("foo", "X") == 3 );
		assert( root.expectTagAttribute!string("foo", "X") == "c" );
		
		// The last "bar" tag doesn't have an int attribute named "X" (only the first "bar" tag does)
		// If you'd rather receive a default value than an exception, use `getAttribute` instead.
		assertThrown!AttributeNotFoundException( root.expectTagAttribute!string("bar", "X") );
		
		// Tag not found
		assertThrown!TagNotFoundException( root.expectTagAttribute!int("doesnt-exist", "X") );

		// Using namespaces:
		root = parseSource(`
			ns1:foo X=1 X="a" X=2 X="b"
			ns1:foo X=3 X="c" X=4 X="d"
			ns2:foo X=11 X="aa" X=22 X="bb"
			ns2:foo X=33 X="cc" X=44 X="dd"
			
			ns1:bar attrNS:X="hi"
			ns1:bar attrNS:X=379  // expectTagAttribute considers this to override the first bar
		`);
		assert( root.expectTagAttribute!int("ns1:foo", "X") == 3  );
		assert( root.expectTagAttribute!int("*:foo",   "X") == 33 ); // Search all namespaces
		
		assert( root.expectTagAttribute!string("ns1:foo", "X") == "c"  );
		assert( root.expectTagAttribute!string("*:foo",   "X") == "cc" ); // Search all namespaces
		
		// bar's attribute X is't in the default namespace
		assertThrown!AttributeNotFoundException( root.expectTagAttribute!int("*:bar", "X") );

		// The last "bar" tag's "attrNS:X" attribute doesn't have a string (only the first "bar" tag does)
		assertThrown!AttributeNotFoundException( root.expectTagAttribute!string("*:bar", "attrNS:X") );

		// Tag's namespace not found
		assertThrown!TagNotFoundException( root.expectTagAttribute!int("doesnt-exist:bar", "attrNS:X") );
	}

	/++
	Lookup a child tag by name, and retrieve all values from it.

	This just like using `getTag()`.`values`, except if the tag isn't found,
	it safely returns null (or an optional array of default values) instead of
	a dereferencing null error.
	
	Note that, unlike `getValue`, this doesn't discriminate by the value's
	type. It simply returns all values of a single tag as a `Value[]`.

	If you'd prefer an exception thrown when the tag isn't found, use
	`expectTag`.`values` instead.
	+/
	Value[] getTagValues(string fullTagName, Value[] defaultValues = null)
	{
		auto tag = getTag(fullTagName);
		if(tag)
			return tag.values;
		else
			return defaultValues;
	}
	
	///
	@("getTagValues")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 "a" 2 "b"
			foo 3 "c" 4 "d"  // getTagValues considers this to override the first foo
		`);
		assert( root.getTagValues("foo") == [Value(3), Value("c"), Value(4), Value("d")] );

		// Tag not found
		// If you'd prefer an exception, use `expectTag.values` instead.
		assert( root.getTagValues("doesnt-exist") is null );
		assert( root.getTagValues("doesnt-exist", [ Value(999), Value("Not found") ]) ==
			[ Value(999), Value("Not found") ] );
	}
	
	/++
	Lookup a child tag by name, and retrieve all attributes in a chosen
	(or default) namespace from it.

	This just like using `getTag()`.`attributes` (or
	`getTag()`.`namespace[...]`.`attributes`, or `getTag()`.`all`.`attributes`),
	except if the tag isn't found, it safely returns an empty range instead
	of a dereferencing null error.
	
	If provided, the `attributeNamespace` parameter can be either the name of
	a namespace, or an empty string for the default namespace (the default),
	or `"*"` to retreive attributes from all namespaces.
	
	Note that, unlike `getAttributes`, this doesn't discriminate by the
	value's type. It simply returns the usual `attributes` range.

	If you'd prefer an exception thrown when the tag isn't found, use
	`expectTag`.`attributes` instead.
	+/
	auto getTagAttributes(string fullTagName, string attributeNamespace = null)
	{
		auto tag = getTag(fullTagName);
		if(tag)
		{
			if(attributeNamespace && attributeNamespace in tag.namespaces)
				return tag.namespaces[attributeNamespace].attributes;
			else if(attributeNamespace == "*")
				return tag.all.attributes;
			else
				return tag.attributes;
		}

		return AttributeRange(null, null, false);
	}
	
	///
	@("getTagAttributes")
	unittest
	{
		import std.exception;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo X=1 X=2
			
			// getTagAttributes considers this to override the first foo
			foo X1=3 X2="c" namespace:bar=7 X3=4 X4="d"
		`);

		auto fooAttrs = root.getTagAttributes("foo");
		assert( !fooAttrs.empty );
		assert( fooAttrs.length == 4 );
		assert( fooAttrs[0].name == "X1" && fooAttrs[0].value == Value(3)   );
		assert( fooAttrs[1].name == "X2" && fooAttrs[1].value == Value("c") );
		assert( fooAttrs[2].name == "X3" && fooAttrs[2].value == Value(4)   );
		assert( fooAttrs[3].name == "X4" && fooAttrs[3].value == Value("d") );

		fooAttrs = root.getTagAttributes("foo", "namespace");
		assert( !fooAttrs.empty );
		assert( fooAttrs.length == 1 );
		assert( fooAttrs[0].name == "bar" && fooAttrs[0].value == Value(7) );

		fooAttrs = root.getTagAttributes("foo", "*");
		assert( !fooAttrs.empty );
		assert( fooAttrs.length == 5 );
		assert( fooAttrs[0].name == "X1"  && fooAttrs[0].value == Value(3)   );
		assert( fooAttrs[1].name == "X2"  && fooAttrs[1].value == Value("c") );
		assert( fooAttrs[2].name == "bar" && fooAttrs[2].value == Value(7)   );
		assert( fooAttrs[3].name == "X3"  && fooAttrs[3].value == Value(4)   );
		assert( fooAttrs[4].name == "X4"  && fooAttrs[4].value == Value("d") );

		// Tag not found
		// If you'd prefer an exception, use `expectTag.attributes` instead.
		assert( root.getTagValues("doesnt-exist").empty );
	}

	@("*: Disallow wildcards for names")
	unittest
	{
		import std.exception;
		import std.math;
		import dub.internal.sdlang.parser;
		
		auto root = parseSource(`
			foo 1 X=2
			ns:foo 3 ns:X=4
		`);
		auto foo = root.getTag("foo");
		auto nsfoo = root.getTag("ns:foo");

		// Sanity check
		assert( foo !is null );
		assert( foo.name == "foo" );
		assert( foo.namespace == "" );

		assert( nsfoo !is null );
		assert( nsfoo.name == "foo" );
		assert( nsfoo.namespace == "ns" );

		assert( foo.getValue     !int() == 1 );
		assert( foo.expectValue  !int() == 1 );
		assert( nsfoo.getValue   !int() == 3 );
		assert( nsfoo.expectValue!int() == 3 );

		assert( root.getTagValue   !int("foo")    == 1 );
		assert( root.expectTagValue!int("foo")    == 1 );
		assert( root.getTagValue   !int("ns:foo") == 3 );
		assert( root.expectTagValue!int("ns:foo") == 3 );

		assert( foo.getAttribute     !int("X")    == 2 );
		assert( foo.expectAttribute  !int("X")    == 2 );
		assert( nsfoo.getAttribute   !int("ns:X") == 4 );
		assert( nsfoo.expectAttribute!int("ns:X") == 4 );

		assert( root.getTagAttribute   !int("foo", "X")       == 2 );
		assert( root.expectTagAttribute!int("foo", "X")       == 2 );
		assert( root.getTagAttribute   !int("ns:foo", "ns:X") == 4 );
		assert( root.expectTagAttribute!int("ns:foo", "ns:X") == 4 );
		
		// No namespace
		assertThrown!ArgumentException( root.getTag   ("*") );
		assertThrown!ArgumentException( root.expectTag("*") );
		
		assertThrown!ArgumentException( root.getTagValue   !int("*") );
		assertThrown!ArgumentException( root.expectTagValue!int("*") );

		assertThrown!ArgumentException( foo.getAttribute       !int("*")        );
		assertThrown!ArgumentException( foo.expectAttribute    !int("*")        );
		assertThrown!ArgumentException( root.getTagAttribute   !int("*", "X")   );
		assertThrown!ArgumentException( root.expectTagAttribute!int("*", "X")   );
		assertThrown!ArgumentException( root.getTagAttribute   !int("foo", "*") );
		assertThrown!ArgumentException( root.expectTagAttribute!int("foo", "*") );

		// With namespace
		assertThrown!ArgumentException( root.getTag   ("ns:*") );
		assertThrown!ArgumentException( root.expectTag("ns:*") );
		
		assertThrown!ArgumentException( root.getTagValue   !int("ns:*") );
		assertThrown!ArgumentException( root.expectTagValue!int("ns:*") );

		assertThrown!ArgumentException( nsfoo.getAttribute     !int("ns:*")           );
		assertThrown!ArgumentException( nsfoo.expectAttribute  !int("ns:*")           );
		assertThrown!ArgumentException( root.getTagAttribute   !int("ns:*",   "ns:X") );
		assertThrown!ArgumentException( root.expectTagAttribute!int("ns:*",   "ns:X") );
		assertThrown!ArgumentException( root.getTagAttribute   !int("ns:foo", "ns:*") );
		assertThrown!ArgumentException( root.expectTagAttribute!int("ns:foo", "ns:*") );

		// With wildcard namespace
		assertThrown!ArgumentException( root.getTag   ("*:*") );
		assertThrown!ArgumentException( root.expectTag("*:*") );
		
		assertThrown!ArgumentException( root.getTagValue   !int("*:*") );
		assertThrown!ArgumentException( root.expectTagValue!int("*:*") );

		assertThrown!ArgumentException( nsfoo.getAttribute     !int("*:*")          );
		assertThrown!ArgumentException( nsfoo.expectAttribute  !int("*:*")          );
		assertThrown!ArgumentException( root.getTagAttribute   !int("*:*",   "*:X") );
		assertThrown!ArgumentException( root.expectTagAttribute!int("*:*",   "*:X") );
		assertThrown!ArgumentException( root.getTagAttribute   !int("*:foo", "*:*") );
		assertThrown!ArgumentException( root.expectTagAttribute!int("*:foo", "*:*") );
	}
	
	override bool opEquals(Object o)
	{
		auto t = cast(Tag)o;
		if(!t)
			return false;
		
		if(_namespace != t._namespace || _name != t._name)
			return false;

		if(
			values        .length != t.values       .length ||
			allAttributes .length != t.allAttributes.length ||
			allNamespaces .length != t.allNamespaces.length ||
			allTags       .length != t.allTags      .length
		)
			return false;
		
		if(values != t.values)
			return false;

		if(allNamespaces != t.allNamespaces)
			return false;

		if(allAttributes != t.allAttributes)
			return false;
		
		// Ok because cycles are not allowed
		//TODO: Actually check for or prevent cycles.
		return allTags == t.allTags;
	}
	
	/// Treats `this` as the root tag. Note that root tags cannot have
	/// values or attributes, and cannot be part of a namespace.
	/// If this isn't a valid root tag, `sdlang.exception.ValidationException`
	/// will be thrown.
	string toSDLDocument()(string indent="\t", int indentLevel=0)
	{
		Appender!string sink;
		toSDLDocument(sink, indent, indentLevel);
		return sink.data;
	}
	
	///ditto
	void toSDLDocument(Sink)(ref Sink sink, string indent="\t", int indentLevel=0)
		if(isOutputRange!(Sink,char))
	{
		if(values.length > 0)
			throw new ValidationException("Root tags cannot have any values, only child tags.");

		if(allAttributes.length > 0)
			throw new ValidationException("Root tags cannot have any attributes, only child tags.");

		if(_namespace != "")
			throw new ValidationException("Root tags cannot have a namespace.");
		
		foreach(tag; allTags)
			tag.toSDLString(sink, indent, indentLevel);
	}
	
	/// Output this entire tag in SDL format. Does $(B $(I not)) treat `this` as
	/// a root tag. If you intend this to be the root of a standard SDL
	/// document, use `toSDLDocument` instead.
	string toSDLString()(string indent="\t", int indentLevel=0)
	{
		Appender!string sink;
		toSDLString(sink, indent, indentLevel);
		return sink.data;
	}
	
	///ditto
	void toSDLString(Sink)(ref Sink sink, string indent="\t", int indentLevel=0)
		if(isOutputRange!(Sink,char))
	{
		if(_name == "" && values.length == 0)
			throw new ValidationException("Anonymous tags must have at least one value.");
		
		if(_name == "" && _namespace != "")
			throw new ValidationException("Anonymous tags cannot have a namespace.");
	
		// Indent
		foreach(i; 0..indentLevel)
			sink.put(indent);
		
		// Name
		if(_namespace != "")
		{
			sink.put(_namespace);
			sink.put(':');
		}
		sink.put(_name);
		
		// Values
		foreach(i, v; values)
		{
			// Omit the first space for anonymous tags
			if(_name != "" || i > 0)
				sink.put(' ');
			
			v.toSDLString(sink);
		}
		
		// Attributes
		foreach(attr; allAttributes)
		{
			sink.put(' ');
			attr.toSDLString(sink);
		}
		
		// Child tags
		bool foundChild=false;
		foreach(tag; allTags)
		{
			if(!foundChild)
			{
				sink.put(" {\n");
				foundChild = true;
			}

			tag.toSDLString(sink, indent, indentLevel+1);
		}
		if(foundChild)
		{
			foreach(i; 0..indentLevel)
				sink.put(indent);

			sink.put("}\n");
		}
		else
			sink.put("\n");
	}

	/// Outputs full information on the tag.
	string toDebugString()
	{
		import std.algorithm : sort;

		Appender!string buf;
		
		buf.put("\n");
		buf.put("Tag ");
		if(_namespace != "")
		{
			buf.put("[");
			buf.put(_namespace);
			buf.put("]");
		}
		buf.put("'%s':\n".format(_name));

		// Values
		foreach(val; values)
			buf.put("    (%s): %s\n".format(.toString(val.type), val));

		// Attributes
		foreach(attrNamespace; _attributes.keys.sort())
		if(attrNamespace != "*")
		foreach(attrName; _attributes[attrNamespace].keys.sort())
		foreach(attr; _attributes[attrNamespace][attrName])
		{
			string namespaceStr;
			if(attr._namespace != "")
				namespaceStr = "["~attr._namespace~"]";
			
			buf.put(
				"    %s%s(%s): %s\n".format(
					namespaceStr, attr._name, .toString(attr.value.type), attr.value
				)
			);
		}
		
		// Children
		foreach(tagNamespace; _tags.keys.sort())
		if(tagNamespace != "*")
		foreach(tagName; _tags[tagNamespace].keys.sort())
		foreach(tag; _tags[tagNamespace][tagName])
			buf.put( tag.toDebugString().replace("\n", "\n    ") );
		
		return buf.data;
	}
}

version(unittest)
{
	private void testRandomAccessRange(R, E)(R range, E[] expected, bool function(E, E) equals=null)
	{
		static assert(isRandomAccessRange!R);
		static assert(is(ElementType!R == E));
		static assert(hasLength!R);
		static assert(!isInfinite!R);

		assert(range.length == expected.length);
		if(range.length == 0)
		{
			assert(range.empty);
			return;
		}
		
		static bool defaultEquals(E e1, E e2)
		{
			return e1 == e2;
		}
		if(equals is null)
			equals = &defaultEquals;
		
		assert(equals(range.front, expected[0]));
		assert(equals(range.front, expected[0]));  // Ensure consistent result from '.front'
		assert(equals(range.front, expected[0]));  // Ensure consistent result from '.front'

		assert(equals(range.back, expected[$-1]));
		assert(equals(range.back, expected[$-1]));  // Ensure consistent result from '.back'
		assert(equals(range.back, expected[$-1]));  // Ensure consistent result from '.back'
		
		// Forward iteration
		auto original = range.save;
		auto r2 = range.save;
		foreach(i; 0..expected.length)
		{
			//trace("Forward iteration: ", i);
			
			// Test length/empty
			assert(range.length == expected.length - i);
			assert(range.length == r2.length);
			assert(!range.empty);
			assert(!r2.empty);
			
			// Test front
			assert(equals(range.front, expected[i]));
			assert(equals(range.front, r2.front));

			// Test back
			assert(equals(range.back, expected[$-1]));
			assert(equals(range.back, r2.back));

			// Test opIndex(0)
			assert(equals(range[0], expected[i]));
			assert(equals(range[0], r2[0]));

			// Test opIndex($-1)
			assert(equals(range[$-1], expected[$-1]));
			assert(equals(range[$-1], r2[$-1]));

			// Test popFront
			range.popFront();
			assert(range.length == r2.length - 1);
			r2.popFront();
			assert(range.length == r2.length);
		}
		assert(range.empty);
		assert(r2.empty);
		assert(original.length == expected.length);
		
		// Backwards iteration
		range = original.save;
		r2    = original.save;
		foreach(i; iota(0, expected.length).retro())
		{
			//trace("Backwards iteration: ", i);

			// Test length/empty
			assert(range.length == i+1);
			assert(range.length == r2.length);
			assert(!range.empty);
			assert(!r2.empty);
			
			// Test front
			assert(equals(range.front, expected[0]));
			assert(equals(range.front, r2.front));

			// Test back
			assert(equals(range.back, expected[i]));
			assert(equals(range.back, r2.back));

			// Test opIndex(0)
			assert(equals(range[0], expected[0]));
			assert(equals(range[0], r2[0]));

			// Test opIndex($-1)
			assert(equals(range[$-1], expected[i]));
			assert(equals(range[$-1], r2[$-1]));

			// Test popBack
			range.popBack();
			assert(range.length == r2.length - 1);
			r2.popBack();
			assert(range.length == r2.length);
		}
		assert(range.empty);
		assert(r2.empty);
		assert(original.length == expected.length);
		
		// Random access
		range = original.save;
		r2    = original.save;
		foreach(i; 0..expected.length)
		{
			//trace("Random access: ", i);

			// Test length/empty
			assert(range.length == expected.length);
			assert(range.length == r2.length);
			assert(!range.empty);
			assert(!r2.empty);
			
			// Test front
			assert(equals(range.front, expected[0]));
			assert(equals(range.front, r2.front));

			// Test back
			assert(equals(range.back, expected[$-1]));
			assert(equals(range.back, r2.back));

			// Test opIndex(i)
			assert(equals(range[i], expected[i]));
			assert(equals(range[i], r2[i]));
		}
		assert(!range.empty);
		assert(!r2.empty);
		assert(original.length == expected.length);
	}
}

@("*: Test sdlang ast")
unittest
{
	import std.exception;
	import dub.internal.sdlang.parser;
	
	Tag root;
	root = parseSource("");
	testRandomAccessRange(root.attributes, cast(          Attribute[])[]);
	testRandomAccessRange(root.tags,       cast(                Tag[])[]);
	testRandomAccessRange(root.namespaces, cast(Tag.NamespaceAccess[])[]);
	
	root = parseSource(`
		blue 3 "Lee" isThree=true
		blue 5 "Chan" 12345 isThree=false
		stuff:orange 1 2 3 2 1
		stuff:square points=4 dimensions=2 points="Still four"
		stuff:triangle data:points=3 data:dimensions=2
		nothing
		namespaces small:A=1 med:A=2 big:A=3 small:B=10 big:B=30
		
		people visitor:a=1 b=2 {
			chiyo "Small" "Flies?" nemesis="Car" score=100
			yukari
			visitor:sana
			tomo
			visitor:hayama
		}
	`);

	auto blue3 = new Tag(
		null, "", "blue",
		[ Value(3), Value("Lee") ],
		[ new Attribute("isThree", Value(true)) ],
		null
	);
	auto blue5 = new Tag(
		null, "", "blue",
		[ Value(5), Value("Chan"), Value(12345) ],
		[ new Attribute("isThree", Value(false)) ],
		null
	);
	auto orange = new Tag(
		null, "stuff", "orange",
		[ Value(1), Value(2), Value(3), Value(2), Value(1) ],
		null,
		null
	);
	auto square = new Tag(
		null, "stuff", "square",
		null,
		[
			new Attribute("points", Value(4)),
			new Attribute("dimensions", Value(2)),
			new Attribute("points", Value("Still four")),
		],
		null
	);
	auto triangle = new Tag(
		null, "stuff", "triangle",
		null,
		[
			new Attribute("data", "points", Value(3)),
			new Attribute("data", "dimensions", Value(2)),
		],
		null
	);
	auto nothing = new Tag(
		null, "", "nothing",
		null, null, null
	);
	auto namespaces = new Tag(
		null, "", "namespaces",
		null,
		[
			new Attribute("small", "A", Value(1)),
			new Attribute("med",   "A", Value(2)),
			new Attribute("big",   "A", Value(3)),
			new Attribute("small", "B", Value(10)),
			new Attribute("big",   "B", Value(30)),
		],
		null
	);
	auto chiyo = new Tag(
		null, "", "chiyo",
		[ Value("Small"), Value("Flies?") ],
		[
			new Attribute("nemesis", Value("Car")),
			new Attribute("score", Value(100)),
		],
		null
	);
	auto chiyo_ = new Tag(
		null, "", "chiyo_",
		[ Value("Small"), Value("Flies?") ],
		[
			new Attribute("nemesis", Value("Car")),
			new Attribute("score", Value(100)),
		],
		null
	);
	auto yukari = new Tag(
		null, "", "yukari",
		null, null, null
	);
	auto sana = new Tag(
		null, "visitor", "sana",
		null, null, null
	);
	auto sana_ = new Tag(
		null, "visitor", "sana_",
		null, null, null
	);
	auto sanaVisitor_ = new Tag(
		null, "visitor_", "sana_",
		null, null, null
	);
	auto tomo = new Tag(
		null, "", "tomo",
		null, null, null
	);
	auto hayama = new Tag(
		null, "visitor", "hayama",
		null, null, null
	);
	auto people = new Tag(
		null, "", "people",
		null,
		[
			new Attribute("visitor", "a", Value(1)),
			new Attribute("b", Value(2)),
		],
		[chiyo, yukari, sana, tomo, hayama]
	);
	
	assert(blue3      .opEquals( blue3      ));
	assert(blue5      .opEquals( blue5      ));
	assert(orange     .opEquals( orange     ));
	assert(square     .opEquals( square     ));
	assert(triangle   .opEquals( triangle   ));
	assert(nothing    .opEquals( nothing    ));
	assert(namespaces .opEquals( namespaces ));
	assert(people     .opEquals( people     ));
	assert(chiyo      .opEquals( chiyo      ));
	assert(yukari     .opEquals( yukari     ));
	assert(sana       .opEquals( sana       ));
	assert(tomo       .opEquals( tomo       ));
	assert(hayama     .opEquals( hayama     ));
	
	assert(!blue3.opEquals(orange));
	assert(!blue3.opEquals(people));
	assert(!blue3.opEquals(sana));
	assert(!blue3.opEquals(blue5));
	assert(!blue5.opEquals(blue3));
	
	alias Tag.NamespaceAccess NSA;
	static bool namespaceEquals(NSA n1, NSA n2)
	{
		return n1.name == n2.name;
	}
	
	testRandomAccessRange(root.attributes, cast(Attribute[])[]);
	testRandomAccessRange(root.tags,       [blue3, blue5, nothing, namespaces, people]);
	testRandomAccessRange(root.namespaces, [NSA(""), NSA("stuff")], &namespaceEquals);
	testRandomAccessRange(root.namespaces[0].tags, [blue3, blue5, nothing, namespaces, people]);
	testRandomAccessRange(root.namespaces[1].tags, [orange, square, triangle]);
	assert(""        in root.namespaces);
	assert("stuff"   in root.namespaces);
	assert("foobar" !in root.namespaces);
	testRandomAccessRange(root.namespaces[     ""].tags, [blue3, blue5, nothing, namespaces, people]);
	testRandomAccessRange(root.namespaces["stuff"].tags, [orange, square, triangle]);
	testRandomAccessRange(root.all.attributes, cast(Attribute[])[]);
	testRandomAccessRange(root.all.tags,       [blue3, blue5, orange, square, triangle, nothing, namespaces, people]);
	testRandomAccessRange(root.all.tags[],     [blue3, blue5, orange, square, triangle, nothing, namespaces, people]);
	testRandomAccessRange(root.all.tags[3..6], [square, triangle, nothing]);
	assert("blue"    in root.tags);
	assert("nothing" in root.tags);
	assert("people"  in root.tags);
	assert("orange" !in root.tags);
	assert("square" !in root.tags);
	assert("foobar" !in root.tags);
	assert("blue"    in root.all.tags);
	assert("nothing" in root.all.tags);
	assert("people"  in root.all.tags);
	assert("orange"  in root.all.tags);
	assert("square"  in root.all.tags);
	assert("foobar" !in root.all.tags);
	assert("orange"  in root.namespaces["stuff"].tags);
	assert("square"  in root.namespaces["stuff"].tags);
	assert("square"  in root.namespaces["stuff"].tags);
	assert("foobar" !in root.attributes);
	assert("foobar" !in root.all.attributes);
	assert("foobar" !in root.namespaces["stuff"].attributes);
	assert("blue"   !in root.attributes);
	assert("blue"   !in root.all.attributes);
	assert("blue"   !in root.namespaces["stuff"].attributes);
	testRandomAccessRange(root.tags["nothing"],                    [nothing]);
	testRandomAccessRange(root.tags["blue"],                       [blue3, blue5]);
	testRandomAccessRange(root.namespaces["stuff"].tags["orange"], [orange]);
	testRandomAccessRange(root.all.tags["nothing"],                [nothing]);
	testRandomAccessRange(root.all.tags["blue"],                   [blue3, blue5]);
	testRandomAccessRange(root.all.tags["orange"],                 [orange]);

	assertThrown!DOMRangeException(root.tags["foobar"]);
	assertThrown!DOMRangeException(root.all.tags["foobar"]);
	assertThrown!DOMRangeException(root.attributes["foobar"]);
	assertThrown!DOMRangeException(root.all.attributes["foobar"]);
	
	// DMD Issue #12585 causes a segfault in these two tests when using 2.064 or 2.065,
	// so work around it.
	//assertThrown!DOMRangeException(root.namespaces["foobar"].tags["foobar"]);
	//assertThrown!DOMRangeException(root.namespaces["foobar"].attributes["foobar"]);
	bool didCatch = false;
	try
		auto x = root.namespaces["foobar"].tags["foobar"];
	catch(DOMRangeException e)
		didCatch = true;
	assert(didCatch);
	
	didCatch = false;
	try
		auto x = root.namespaces["foobar"].attributes["foobar"];
	catch(DOMRangeException e)
		didCatch = true;
	assert(didCatch);

	testRandomAccessRange(root.maybe.tags["nothing"],                    [nothing]);
	testRandomAccessRange(root.maybe.tags["blue"],                       [blue3, blue5]);
	testRandomAccessRange(root.maybe.namespaces["stuff"].tags["orange"], [orange]);
	testRandomAccessRange(root.maybe.all.tags["nothing"],                [nothing]);
	testRandomAccessRange(root.maybe.all.tags["blue"],                   [blue3, blue5]);
	testRandomAccessRange(root.maybe.all.tags["blue"][],                 [blue3, blue5]);
	testRandomAccessRange(root.maybe.all.tags["blue"][0..1],             [blue3]);
	testRandomAccessRange(root.maybe.all.tags["blue"][1..2],             [blue5]);
	testRandomAccessRange(root.maybe.all.tags["orange"],                 [orange]);
	testRandomAccessRange(root.maybe.tags["foobar"],                      cast(Tag[])[]);
	testRandomAccessRange(root.maybe.all.tags["foobar"],                  cast(Tag[])[]);
	testRandomAccessRange(root.maybe.namespaces["foobar"].tags["foobar"], cast(Tag[])[]);
	testRandomAccessRange(root.maybe.attributes["foobar"],                      cast(Attribute[])[]);
	testRandomAccessRange(root.maybe.all.attributes["foobar"],                  cast(Attribute[])[]);
	testRandomAccessRange(root.maybe.namespaces["foobar"].attributes["foobar"], cast(Attribute[])[]);

	testRandomAccessRange(blue3.attributes,     [ new Attribute("isThree", Value(true)) ]);
	testRandomAccessRange(blue3.tags,           cast(Tag[])[]);
	testRandomAccessRange(blue3.namespaces,     [NSA("")], &namespaceEquals);
	testRandomAccessRange(blue3.all.attributes, [ new Attribute("isThree", Value(true)) ]);
	testRandomAccessRange(blue3.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(blue5.attributes,     [ new Attribute("isThree", Value(false)) ]);
	testRandomAccessRange(blue5.tags,           cast(Tag[])[]);
	testRandomAccessRange(blue5.namespaces,     [NSA("")], &namespaceEquals);
	testRandomAccessRange(blue5.all.attributes, [ new Attribute("isThree", Value(false)) ]);
	testRandomAccessRange(blue5.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(orange.attributes,     cast(Attribute[])[]);
	testRandomAccessRange(orange.tags,           cast(Tag[])[]);
	testRandomAccessRange(orange.namespaces,     cast(NSA[])[], &namespaceEquals);
	testRandomAccessRange(orange.all.attributes, cast(Attribute[])[]);
	testRandomAccessRange(orange.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(square.attributes, [
		new Attribute("points", Value(4)),
		new Attribute("dimensions", Value(2)),
		new Attribute("points", Value("Still four")),
	]);
	testRandomAccessRange(square.tags,       cast(Tag[])[]);
	testRandomAccessRange(square.namespaces, [NSA("")], &namespaceEquals);
	testRandomAccessRange(square.all.attributes, [
		new Attribute("points", Value(4)),
		new Attribute("dimensions", Value(2)),
		new Attribute("points", Value("Still four")),
	]);
	testRandomAccessRange(square.all.tags, cast(Tag[])[]);
	
	testRandomAccessRange(triangle.attributes, cast(Attribute[])[]);
	testRandomAccessRange(triangle.tags,       cast(Tag[])[]);
	testRandomAccessRange(triangle.namespaces, [NSA("data")], &namespaceEquals);
	testRandomAccessRange(triangle.namespaces[0].attributes, [
		new Attribute("data", "points", Value(3)),
		new Attribute("data", "dimensions", Value(2)),
	]);
	assert("data"    in triangle.namespaces);
	assert("foobar" !in triangle.namespaces);
	testRandomAccessRange(triangle.namespaces["data"].attributes, [
		new Attribute("data", "points", Value(3)),
		new Attribute("data", "dimensions", Value(2)),
	]);
	testRandomAccessRange(triangle.all.attributes, [
		new Attribute("data", "points", Value(3)),
		new Attribute("data", "dimensions", Value(2)),
	]);
	testRandomAccessRange(triangle.all.tags, cast(Tag[])[]);
	
	testRandomAccessRange(nothing.attributes,     cast(Attribute[])[]);
	testRandomAccessRange(nothing.tags,           cast(Tag[])[]);
	testRandomAccessRange(nothing.namespaces,     cast(NSA[])[], &namespaceEquals);
	testRandomAccessRange(nothing.all.attributes, cast(Attribute[])[]);
	testRandomAccessRange(nothing.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(namespaces.attributes,   cast(Attribute[])[]);
	testRandomAccessRange(namespaces.tags,         cast(Tag[])[]);
	testRandomAccessRange(namespaces.namespaces,   [NSA("small"), NSA("med"), NSA("big")], &namespaceEquals);
	testRandomAccessRange(namespaces.namespaces[], [NSA("small"), NSA("med"), NSA("big")], &namespaceEquals);
	testRandomAccessRange(namespaces.namespaces[1..2], [NSA("med")], &namespaceEquals);
	testRandomAccessRange(namespaces.namespaces[0].attributes, [
		new Attribute("small", "A", Value(1)),
		new Attribute("small", "B", Value(10)),
	]);
	testRandomAccessRange(namespaces.namespaces[1].attributes, [
		new Attribute("med", "A", Value(2)),
	]);
	testRandomAccessRange(namespaces.namespaces[2].attributes, [
		new Attribute("big", "A", Value(3)),
		new Attribute("big", "B", Value(30)),
	]);
	testRandomAccessRange(namespaces.namespaces[1..2][0].attributes, [
		new Attribute("med", "A", Value(2)),
	]);
	assert("small"   in namespaces.namespaces);
	assert("med"     in namespaces.namespaces);
	assert("big"     in namespaces.namespaces);
	assert("foobar" !in namespaces.namespaces);
	assert("small"  !in namespaces.namespaces[1..2]);
	assert("med"     in namespaces.namespaces[1..2]);
	assert("big"    !in namespaces.namespaces[1..2]);
	assert("foobar" !in namespaces.namespaces[1..2]);
	testRandomAccessRange(namespaces.namespaces["small"].attributes, [
		new Attribute("small", "A", Value(1)),
		new Attribute("small", "B", Value(10)),
	]);
	testRandomAccessRange(namespaces.namespaces["med"].attributes, [
		new Attribute("med", "A", Value(2)),
	]);
	testRandomAccessRange(namespaces.namespaces["big"].attributes, [
		new Attribute("big", "A", Value(3)),
		new Attribute("big", "B", Value(30)),
	]);
	testRandomAccessRange(namespaces.all.attributes, [
		new Attribute("small", "A", Value(1)),
		new Attribute("med",   "A", Value(2)),
		new Attribute("big",   "A", Value(3)),
		new Attribute("small", "B", Value(10)),
		new Attribute("big",   "B", Value(30)),
	]);
	testRandomAccessRange(namespaces.all.attributes[], [
		new Attribute("small", "A", Value(1)),
		new Attribute("med",   "A", Value(2)),
		new Attribute("big",   "A", Value(3)),
		new Attribute("small", "B", Value(10)),
		new Attribute("big",   "B", Value(30)),
	]);
	testRandomAccessRange(namespaces.all.attributes[2..4], [
		new Attribute("big",   "A", Value(3)),
		new Attribute("small", "B", Value(10)),
	]);
	testRandomAccessRange(namespaces.all.tags, cast(Tag[])[]);
	assert("A"      !in namespaces.attributes);
	assert("B"      !in namespaces.attributes);
	assert("foobar" !in namespaces.attributes);
	assert("A"       in namespaces.all.attributes);
	assert("B"       in namespaces.all.attributes);
	assert("foobar" !in namespaces.all.attributes);
	assert("A"       in namespaces.namespaces["small"].attributes);
	assert("B"       in namespaces.namespaces["small"].attributes);
	assert("foobar" !in namespaces.namespaces["small"].attributes);
	assert("A"       in namespaces.namespaces["med"].attributes);
	assert("B"      !in namespaces.namespaces["med"].attributes);
	assert("foobar" !in namespaces.namespaces["med"].attributes);
	assert("A"       in namespaces.namespaces["big"].attributes);
	assert("B"       in namespaces.namespaces["big"].attributes);
	assert("foobar" !in namespaces.namespaces["big"].attributes);
	assert("foobar" !in namespaces.tags);
	assert("foobar" !in namespaces.all.tags);
	assert("foobar" !in namespaces.namespaces["small"].tags);
	assert("A"      !in namespaces.tags);
	assert("A"      !in namespaces.all.tags);
	assert("A"      !in namespaces.namespaces["small"].tags);
	testRandomAccessRange(namespaces.namespaces["small"].attributes["A"], [
		new Attribute("small", "A", Value(1)),
	]);
	testRandomAccessRange(namespaces.namespaces["med"].attributes["A"], [
		new Attribute("med", "A", Value(2)),
	]);
	testRandomAccessRange(namespaces.namespaces["big"].attributes["A"], [
		new Attribute("big", "A", Value(3)),
	]);
	testRandomAccessRange(namespaces.all.attributes["A"], [
		new Attribute("small", "A", Value(1)),
		new Attribute("med",   "A", Value(2)),
		new Attribute("big",   "A", Value(3)),
	]);
	testRandomAccessRange(namespaces.all.attributes["B"], [
		new Attribute("small", "B", Value(10)),
		new Attribute("big",   "B", Value(30)),
	]);

	testRandomAccessRange(chiyo.attributes, [
		new Attribute("nemesis", Value("Car")),
		new Attribute("score", Value(100)),
	]);
	testRandomAccessRange(chiyo.tags,       cast(Tag[])[]);
	testRandomAccessRange(chiyo.namespaces, [NSA("")], &namespaceEquals);
	testRandomAccessRange(chiyo.all.attributes, [
		new Attribute("nemesis", Value("Car")),
		new Attribute("score", Value(100)),
	]);
	testRandomAccessRange(chiyo.all.tags, cast(Tag[])[]);
	
	testRandomAccessRange(yukari.attributes,     cast(Attribute[])[]);
	testRandomAccessRange(yukari.tags,           cast(Tag[])[]);
	testRandomAccessRange(yukari.namespaces,     cast(NSA[])[], &namespaceEquals);
	testRandomAccessRange(yukari.all.attributes, cast(Attribute[])[]);
	testRandomAccessRange(yukari.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(sana.attributes,     cast(Attribute[])[]);
	testRandomAccessRange(sana.tags,           cast(Tag[])[]);
	testRandomAccessRange(sana.namespaces,     cast(NSA[])[], &namespaceEquals);
	testRandomAccessRange(sana.all.attributes, cast(Attribute[])[]);
	testRandomAccessRange(sana.all.tags,       cast(Tag[])[]);
	
	testRandomAccessRange(people.attributes,         [new Attribute("b", Value(2))]);
	testRandomAccessRange(people.tags,               [chiyo, yukari, tomo]);
	testRandomAccessRange(people.namespaces,         [NSA("visitor"), NSA("")], &namespaceEquals);
	testRandomAccessRange(people.namespaces[0].attributes, [new Attribute("visitor", "a", Value(1))]);
	testRandomAccessRange(people.namespaces[1].attributes, [new Attribute("b", Value(2))]);
	testRandomAccessRange(people.namespaces[0].tags,       [sana, hayama]);
	testRandomAccessRange(people.namespaces[1].tags,       [chiyo, yukari, tomo]);
	assert("visitor" in people.namespaces);
	assert(""        in people.namespaces);
	assert("foobar" !in people.namespaces);
	testRandomAccessRange(people.namespaces["visitor"].attributes, [new Attribute("visitor", "a", Value(1))]);
	testRandomAccessRange(people.namespaces[       ""].attributes, [new Attribute("b", Value(2))]);
	testRandomAccessRange(people.namespaces["visitor"].tags,       [sana, hayama]);
	testRandomAccessRange(people.namespaces[       ""].tags,       [chiyo, yukari, tomo]);
	testRandomAccessRange(people.all.attributes, [
		new Attribute("visitor", "a", Value(1)),
		new Attribute("b", Value(2)),
	]);
	testRandomAccessRange(people.all.tags, [chiyo, yukari, sana, tomo, hayama]);
	
	people.attributes["b"][0].name = "b_";
	people.namespaces["visitor"].attributes["a"][0].name = "a_";
	people.tags["chiyo"][0].name = "chiyo_";
	people.namespaces["visitor"].tags["sana"][0].name = "sana_";

	assert("b_"     in people.attributes);
	assert("a_"     in people.namespaces["visitor"].attributes);
	assert("chiyo_" in people.tags);
	assert("sana_"  in people.namespaces["visitor"].tags);

	assert(people.attributes["b_"][0]                       == new Attribute("b_", Value(2)));
	assert(people.namespaces["visitor"].attributes["a_"][0] == new Attribute("visitor", "a_", Value(1)));
	assert(people.tags["chiyo_"][0]                         == chiyo_);
	assert(people.namespaces["visitor"].tags["sana_"][0]    == sana_);

	assert("b"     !in people.attributes);
	assert("a"     !in people.namespaces["visitor"].attributes);
	assert("chiyo" !in people.tags);
	assert("sana"  !in people.namespaces["visitor"].tags);

	assert(people.maybe.attributes["b"].length                       == 0);
	assert(people.maybe.namespaces["visitor"].attributes["a"].length == 0);
	assert(people.maybe.tags["chiyo"].length                         == 0);
	assert(people.maybe.namespaces["visitor"].tags["sana"].length    == 0);

	people.tags["tomo"][0].remove();
	people.namespaces["visitor"].tags["hayama"][0].remove();
	people.tags["chiyo_"][0].remove();
	testRandomAccessRange(people.tags,               [yukari]);
	testRandomAccessRange(people.namespaces,         [NSA("visitor"), NSA("")], &namespaceEquals);
	testRandomAccessRange(people.namespaces[0].tags, [sana_]);
	testRandomAccessRange(people.namespaces[1].tags, [yukari]);
	assert("visitor" in people.namespaces);
	assert(""        in people.namespaces);
	assert("foobar" !in people.namespaces);
	testRandomAccessRange(people.namespaces["visitor"].tags, [sana_]);
	testRandomAccessRange(people.namespaces[       ""].tags, [yukari]);
	testRandomAccessRange(people.all.tags, [yukari, sana_]);
	
	people.attributes["b_"][0].namespace = "_";
	people.namespaces["visitor"].attributes["a_"][0].namespace = "visitor_";
	assert("_"         in people.namespaces);
	assert("visitor_"  in people.namespaces);
	assert(""          in people.namespaces);
	assert("visitor"   in people.namespaces);
	people.namespaces["visitor"].tags["sana_"][0].namespace = "visitor_";
	assert("_"         in people.namespaces);
	assert("visitor_"  in people.namespaces);
	assert(""          in people.namespaces);
	assert("visitor"  !in people.namespaces);

	assert(people.namespaces["_"       ].attributes["b_"][0] == new Attribute("_", "b_", Value(2)));
	assert(people.namespaces["visitor_"].attributes["a_"][0] == new Attribute("visitor_", "a_", Value(1)));
	assert(people.namespaces["visitor_"].tags["sana_"][0]    == sanaVisitor_);
	
	people.tags["yukari"][0].remove();
	people.namespaces["visitor_"].tags["sana_"][0].remove();
	people.namespaces["visitor_"].attributes["a_"][0].namespace = "visitor";
	people.namespaces["_"].attributes["b_"][0].namespace = "";
	testRandomAccessRange(people.tags,               cast(Tag[])[]);
	testRandomAccessRange(people.namespaces,         [NSA("visitor"), NSA("")], &namespaceEquals);
	testRandomAccessRange(people.namespaces[0].tags, cast(Tag[])[]);
	testRandomAccessRange(people.namespaces[1].tags, cast(Tag[])[]);
	assert("visitor" in people.namespaces);
	assert(""        in people.namespaces);
	assert("foobar" !in people.namespaces);
	testRandomAccessRange(people.namespaces["visitor"].tags, cast(Tag[])[]);
	testRandomAccessRange(people.namespaces[       ""].tags, cast(Tag[])[]);
	testRandomAccessRange(people.all.tags, cast(Tag[])[]);
	
	people.namespaces["visitor"].attributes["a_"][0].remove();
	testRandomAccessRange(people.attributes,               [new Attribute("b_", Value(2))]);
	testRandomAccessRange(people.namespaces,               [NSA("")], &namespaceEquals);
	testRandomAccessRange(people.namespaces[0].attributes, [new Attribute("b_", Value(2))]);
	assert("visitor" !in people.namespaces);
	assert(""         in people.namespaces);
	assert("foobar"  !in people.namespaces);
	testRandomAccessRange(people.namespaces[""].attributes, [new Attribute("b_", Value(2))]);
	testRandomAccessRange(people.all.attributes, [
		new Attribute("b_", Value(2)),
	]);
	
	people.attributes["b_"][0].remove();
	testRandomAccessRange(people.attributes, cast(Attribute[])[]);
	testRandomAccessRange(people.namespaces, cast(NSA[])[], &namespaceEquals);
	assert("visitor" !in people.namespaces);
	assert(""        !in people.namespaces);
	assert("foobar"  !in people.namespaces);
	testRandomAccessRange(people.all.attributes, cast(Attribute[])[]);
	
	// Test clone()
	auto rootClone = root.clone();
	assert(rootClone !is root);
	assert(rootClone.parent is null);
	assert(rootClone.name      == root.name);
	assert(rootClone.namespace == root.namespace);
	assert(rootClone.location  == root.location);
	assert(rootClone.values    == root.values);
	assert(rootClone.toSDLDocument() == root.toSDLDocument());

	auto peopleClone = people.clone();
	assert(peopleClone !is people);
	assert(peopleClone.parent is null);
	assert(peopleClone.name      == people.name);
	assert(peopleClone.namespace == people.namespace);
	assert(peopleClone.location  == people.location);
	assert(peopleClone.values    == people.values);
	assert(peopleClone.toSDLString() == people.toSDLString());
}

// Regression test, issue #11: https://github.com/Abscissa/SDLang-D/issues/11
@("*: Regression test issue #11")
unittest
{
	import dub.internal.sdlang.parser;

	auto root = parseSource(
`//
a`);

	assert("a" in root.tags);

	root = parseSource(
`//
parent {
	child
}
`);

	auto child = new Tag(
		null, "", "child",
		null, null, null
	);
	
	assert("parent" in root.tags);
	assert("child" !in root.tags);
	testRandomAccessRange(root.tags["parent"][0].tags, [child]);
	assert("child" in root.tags["parent"][0].tags);
}

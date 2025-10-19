module PCMMXML

using XML

export get_elements_by_tagname, find_element, simple_content, set_simple_content, root, create_xml_document, add_child_element

"""
    get_elements_by_tagname(e::XML.AbstractXMLNode, tagname::AbstractString)

Get all child elements of `e` with the given `tagname`.
"""
function get_elements_by_tagname(e::XML.AbstractXMLNode, tagname::AbstractString)
    return filter(x -> tag(x) == tagname, children(e))
end

"""
    find_element(e::XML.AbstractXMLNode, tagname::AbstractString)

Find the first child element of `e` with the given `tagname`. Returns `nothing` if no such child exists.
"""
function find_element(e::XML.AbstractXMLNode, tagname::AbstractString)
    for child in children(e)
        if tag(child) == tagname
            return child
        end
    end
    return nothing
end

"""
    simple_content(e::XML.AbstractXMLNode)

Get the text content of the XML element `e` of the form `<tag attrbs...>content</tag>`.
"""
function simple_content(e::XML.AbstractXMLNode)
    c = children(e)
    l = length(c)
    if l == 0
        throw(AssertionError("""
        PCMMXML: Asked for simple_content of $(tag(e)), but it has no children.
        - <tag>1.0</tag> is a Node with one child: the Text node "1.0".
        - This is your element:
        $(XML.write(e))
        """))
    elseif l > 1
        throw(AssertionError("""
        PCMMXML: Asked for simple_content of $(tag(e)), but it has multiple children.
        - <tag>1.0</tag> is a Node with one child: the Text node "1.0".
        - This is your element:
        $(XML.write(e))
        """))
    else
        @assert nodetype(first(c)) in (XML.Text, XML.CData) "Element $(tag(e)) does not have text or CDATA content. Cannot get simple_content."
        return value(first(c))
    end
end

"""
    set_simple_content(e::XML.AbstractXMLNode, new_content::String)

Set the text content of the XML element `e` to `new_content`. If `e` has no content, a new text node is added.
"""
function set_simple_content(e::Node, new_content::String)
    c = children(e)
    l = length(c)
    if l == 0
        push!(e, Node(new_content))
    elseif l > 1
        throw(AssertionError("""
        PCMMXML: Asked to set_simple_content of $(tag(e)), but it has multiple children.
        - <tag>1.0</tag> is a Node with one child: the Text node "1.0".
        - This is your element:
        $(XML.write(e))
        """))
    else
        @assert nodetype(first(c)) in (XML.Text, XML.CData) "Element $(tag(e)) does not have text or CDATA content. Cannot set content."
        e[1] = new_content
    end
end

"""
    root(xml_doc::XML.AbstractXMLNode)

Get the root element of the XML document `xml_doc`.
"""
function root(xml_doc::XML.AbstractXMLNode)
    @assert XML.nodetype(xml_doc) == XML.Document "Can only get root of XML Document."
    return last(children(xml_doc))
end

"""
    create_xml_document(root::XML.AbstractXMLNode)

Create a new XML document with the given `root` element.
Add the XML declaration with version "1.0".
"""
function create_xml_document(root::XML.AbstractXMLNode)
    @assert XML.nodetype(root) == XML.Element "Root must be an XML Element."
    return Node(XML.Document, nothing, nothing, nothing, [Node(XML.Declaration, nothing, Dict("version" => "1.0"), nothing, nothing), root])
end

function add_child_element(parent::XML.AbstractXMLNode, tagname::AbstractString, content::Union{Nothing,AbstractString}=nothing; kwargs...)
    @assert !isnothing(children(parent)) "Cannot add child to a node that has no children."
    if isnothing(content)
        new_element = XML.h(tagname; kwargs...)
    else
        new_element = XML.h(tagname, content; kwargs...)
    end
    push!(parent, new_element)
    return new_element
end

end
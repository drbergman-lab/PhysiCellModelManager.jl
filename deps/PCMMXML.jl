module PCMMXML

using XML

export get_elements_by_tagname, find_element, content, set_content, root

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
    has_content(e::XML.AbstractXMLNode)

Check if the XML element `e` has text content.
"""
has_content(e::XML.AbstractXMLNode) = nodetype(e) == XML.Element && nodetype(only(e)) in (XML.Text, XML.CData)

"""
    content(e::XML.AbstractXMLNode)

Get the text content of the XML element `e`. Throws an error if `e` has no content.
"""
content(e::XML.AbstractXMLNode) = has_content(e) ? value(only(e)) : error("PCMMXML: Asked for content of $(tag(e)), but it has none.")

"""
    set_content(e::XML.AbstractXMLNode, new_content::String)

Set the text content of the XML element `e` to `new_content`. If `e` has no content, a new text node is added.
"""
function set_content(e::Node, new_content::String)
    if isempty(children(e))
        push!(e, Node(new_content))
        return
    end
    @assert nodetype(only(e)) in (XML.Text, XML.CData) "Element ($e) has no content, cannot set content"
    e[1] = new_content
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

end
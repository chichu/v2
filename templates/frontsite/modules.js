/*
 * Module ID & link definitions
 * Format:
 * moduleId:{url: "url_of_this_module",
 *  		 t:   "title_for_this_module",
 *   		 c:   "optional color definition for title bar"}
 */ 
var _modules={
    {% for w in widgets %}
	m{{w.id}}:{url:"/widget/w/?id={{w.id}}",	t:"{{w.name}}", c:"{{w.color}}",seturl:"/widget/w_set/?id={{w.id}}"}{% if not forloop.last %},{% endif %}
	{% endfor %}
};

/*
 * Layout definitions for each tab, i.e., which modules go to which columns under which tab
 *  Format:
 *  	{id: "id_of_the_module	(refer to _modules)",
 *  	 c:  "column_id_belongs_to	(c1, c2, c3)",
 *  	 t:  "tab_id_belongs_to	(t1, t2, ...)"}
 */ 
var _moduleLayout=[
    {% for w in widgets %}
	{id:'m{{w.id}}',c:'c{{forloop.counter}}',tab:'t{{w.tab.id}}'}{% if not forloop.last %},{% endif %}
	{% endfor %}
];

/* 
 * Column layout definitions, i.e., how the columns (containers) are placed under each tab
 * Pure CSS properties can be set upon each column, e.g., width, float, etc. You can refer
 * to jQuery.fn.css() for more details.
 * 
 * The "bg" property is used to set the background of all columns, which actually affects the <body>
 * 
 * A _default value set is provided, to save your efforts of setting each tab manually
 */
{% load tools %}
var _columnLayout = {
	_default: { bg:'normal',
		{% for w in widgets %}c{{forloop.counter}}:'span-12{{w.js}}',
		{% endfor %}
		chelp:'span-24 last'
	}
};
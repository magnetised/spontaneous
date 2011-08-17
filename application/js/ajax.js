// console.log("Loading Ajax...");

Spontaneous.Ajax = (function($, S) {
	$.ajaxSetup({
		'async': true,
		'cache': false,
		'dataType': 'json',
		'ifModified': true
	});
	return {
		namespace: "/@spontaneous",
		get: function(url, callback) {
			var handle_response = function(data, textStatus, xhr) {
				if (textStatus !== 'success') {
					xhr = data;
					data = {};
				}
				callback(data, textStatus, xhr);
			};
			$.ajax({
				'url': this.request_url(url),
				'success': handle_response,
				'data': this.api_access_key(),
				'error': handle_response // pass the error to the handler too
			});
		},
		post: function(url, post_data, callback) {
			var success = function(data, textStatus, XMLHttpRequest) {
				callback(data, textStatus, XMLHttpRequest);
			};
			var error = function(XMLHttpRequest, textStatus, error_thrown) {
				var data = false;
				try {
					data = $.parseJSON(XMLHttpRequest.responseText);
				} catch (e) { }
				callback(data, textStatus, XMLHttpRequest);
			};
			post_data = $.extend(post_data, this.api_access_key());
			$.ajax({
				'url': this.request_url(url),
				'type': 'post',
				'data': post_data,
				'success': success,
				'error': error
			});
		},
		test_field_versions: function(target, fields, success, failure) {
			var version_data = {}, modified = 0;
			for (var i = 0, ii = fields.length; i < ii; i++) {
				var field = fields[i], key = "[fields]["+field.schema_id()+"]";
				if (field.is_modified()) {
					version_data[key] = field.version();
					modified++;
				}
			}
			if (modified === 0) { success(); }

			this.post(['/version', target.id()].join('/'), version_data, function(data, textStatus, xhr) {
				if (textStatus === 'success') {
					success();
				} else {
					if (xhr.status === 409) {
						var field_map = {};
						for (var i = 0, ii = fields.length; i < ii; i++) {
							var f = fields[i];
							field_map[f.schema_id()] = f;
						}
						var conflicted_fields = [];
						for (var sid in data) {
							if (data.hasOwnProperty(sid)) {
								var values = data[sid], field = field_map[sid];
								conflicted_fields.push({
									field:field,
									version: values[0],
									values: {
										server_original: values[1],
										local_edited:  field.edited_value(),
										local_original:  field.original_value()
									}
								});
							}
						}
						failure(conflicted_fields)
					}
				}
			});
		},
		api_access_key: function() {
			return {'__key':Spontaneous.Auth.Key.load(S.site_id)}
		},
		request_url: function(url, needs_key) {
			var path = this.namespace + url;
			if (needs_key) {
				path += "?"+$.param(this.api_access_key())
			}
			return path
		}
	};
}(jQuery, Spontaneous));

// console.log("Loading TopBar...")

Spontaneous.TopBar = (function($, S) {
	var dom = S.Dom;

	var RootNode = function(page) {
		this.page = page;
		this.id = page.id;
		this.url = page.url;
		this.title = page.title;
	}
	RootNode.prototype = {
		element: function() {
			var li = dom.li('.root');
			var link = dom.a({'href': this.url}).text(this.title).data('page', this.page);
			link.click(function() {
				var page = $(this).data('page');
				S.Location.load_id(page.id);
				return false;
			});
			li.append(link);
			return li;
		}
	}

	var AncestorNode = function(page) {
		this.page = page;
		this.id = page.id;
		this.title = page.title;
		this.path = page.path;
	};
	AncestorNode.prototype = {
		element: function() {
			var link = dom.li().append($('<a/>').data('page', this.page).click(function() {
				var page = $(this).data('page');
				S.Location.load_id(page.id);
			}).text(this.title));

			return link;
		}
	};
	var CurrentNode = function(page) {
		this.page = page;
		this.id = page.id;
		this.path = page.path;
		this.title = page.title;
		this.pages = page.generation.sort(function(p1, p2) {
			var a = p1.title, b = p2.title;
			if (a == b) return 0;
			return (a < b ? -1 : 1);
		});
		for (var i = 0, ii = this.pages.length; i < ii; i++) {
			var p = this.pages[i];
			if (p.id === this.id) {
				this.selected = i;
				break;
			}
		}
	}

	CurrentNode.prototype = {
		element: function() {
			var li = dom.li();
			var select = dom.select();
			select.change(function() {
				var page = $(this.options[this.selectedIndex]).data('page');
				S.Location.load_id(page.id);
				return false;
			});
			for (var i = 0, ii = this.pages.length; i < ii; i++) {
				var p = this.pages[i],
				option = dom.option({'value': p.id, 'selected':(i == this.selected) }).text(p.title).data('page', p);
				if (p.id === this.id) {
					this.title_option = option;
				}
				select.append(option);
			};
			li.append(select);
			// select.hide();
			// var link = $(dom.li).append($('<a/>').data('page', this.page).click(function() {
			// 	// var page = $(this).data('page');
			// 	// S.Location.load_id(page.id);
			// 	select.toggle().trigger('click');
			// }).text(this.title));
			//
			// link.append(select);
			// return link;
			return li;
		},
		set_title: function(new_title) {
			this.title_option.text(new_title);
		}
	}

	var ChildrenNode = function(children) {
		this.children = children.sort(function(p1, p2) {
			var a = p1.title, b = p2.title;
			if (a == b) return 0;
			return (a < b ? -1 : 1);
		});
		// for (var i = 0, ii = children.length; i < ii; i++) {
		// 	children[i].title_field().watch('value', function(title) {
		// 		console.log('upating title for page', children[i], title)
		// 	})
		// }

	}

	ChildrenNode.prototype = {
		element: function() {
			var li = dom.li();
			var select = dom.select('.unselected');
			select.append(dom.option().text(this.status_text()));
			select.change(function() {
				var p = $(this.options[this.selectedIndex]).data('page');
				if (p) {
					S.Location.load_id(p.id);
				}
				return false;
			});
			for (var i = 0, ii = this.children.length; i < ii; i++) {
				var p = this.children[i];
				select.append(this.option_for_entry(p));
			};
			li.append(select);
			this.li = li;
			this.select = select;
			return li;
		},
		status_text: function() {
			return '('+(this.children.length)+' pages)';
		},
		option_for_entry: function(p) {
			return dom.option({'value': p.id}).text(p.title).data('page', p);
		},
		update_status: function() {
			var first = this.select.find('option:first-child');
			first.text(this.status_text());
			return first;
		},
		add_page: function(page, position) {
			this.children.splice(0, 0, page)
			var first = this.update_status();
			first.after(this.option_for_entry(page));
		},

		remove_page: function(page) {
			var index = 0;
			for (var i = 0, ii = this.children.length; i < ii; i++) {
				if (this.children[i].id === page.id) {
					index = i;
					break;
				};
			}
			this.children.splice(index, 1);
			this.update_status();
			var options = this.select.find('option:gt(0)'), remove;
			console.log(options)
			options.each(function() {
				console.log('remove?', $(this).data('page').id ,page.id())
				if ($(this).data('page').id === page.id()) {
					$(this).remove();
				}
			});
		}
	}

	var PublishButton = new JS.Class({
		rapid_check: 2000,
		normal_check: 10000,
		initialize: function() {
			this.status = false;
			this.set_interval(this.normal_check);
			this.check_status();
		},
		check_status: function() {
			S.Ajax.get('/publish/status', this.status_recieved.bind(this));
		},
		status_recieved: function(status, response_code) {
			if (response_code === 'success' && status != this.status) {
				this.update_status(status);
			}
			window.setTimeout(this.check_status.bind(this), this.timer_interval);
		},
		update_status: function(status) {
			if (status === null || status === '') { return; }
			var action = status.status, progress = status.progress
			if (this.in_progress && (action == this.current_action && progress == this.current_progress)) { return; }
			this.current_action = action;
			this.current_progress = progress;
			if (action === null || action === '' || action === 'complete' || action === 'error') {
				if (this.in_progress) {
					this.in_progress = false;
					this.progress().stop();
					this.set_interval(this.normal_check);
					this.set_label("Publish");
					this.button().switchClass('progress', '')
					this.current_action = this.current_progress = null;
				}
				if (action === 'error') {
					alert('There was a problem publishing: ' + progress)
				}
			} else {
				this.publishing_state();
				if (action === 'rendering') {
					this.progress().update(progress);
				} else {
					this.progress().indeterminate();
				}
			}
		},
		publishing_started: function() {
			this.publishing_state();
			this.progress().indeterminate();
		},
		publishing_state: function() {
			this.set_interval(this.rapid_check);
			this.set_label("Publishing");
			var b = this.button();
			this.current_action = this.current_progress = null;
			if (!b.hasClass('progress')) { b.switchClass('', 'progress'); }
			this.in_progress = true;
		},
		set_label: function(label) {
			if (label !== this._label_text) {
				this._label_text = label;
				this._label.text(label);
			}
		},
		button: function() {
			if (!this._button) {
				this._progress_container = dom.span('#publish-progress');
				this._label = dom.span();
				this._button = dom.a('#open-publish').append(this._progress_container).append(this._label);
				this.set_label("Publish");
				this._button.click(function() {
					if (!this.in_progress) {
						S.Publishing.open_dialogue();
					}
				}.bind(this));
			}
			return this._button
		},
		progress: function() {
			if (!this._progress) {
				this._progress = Spontaneous.Progress('publish-progress', 15, {
					spinner_fg_color: '#ccc',
					progress_fg_color: '#666'
				});
				this._progress.init();
			}
			return this._progress;
		},
		set_interval: function(milliseconds) {
			this.timer_interval = milliseconds;
		}
	});
	var TopBar = new JS.Singleton({
		include: Spontaneous.Properties,
		location: "/",
		panel: function() {
			this.wrap = dom.div('#top');
			this.location = dom.ul('#navigation');
			this.location.append(dom.li().append(dom.a()))
			this.mode_switch = dom.a('#switch-mode').
				text(this.opposite_mode(S.ContentArea.mode)).
				click(function() {
					S.TopBar.toggle_modes();
			});
			this.publish_button = new PublishButton();
			this.wrap.append(this.location);
			this.wrap.append(this.publish_button.button());
			this.wrap.append(this.mode_switch);
			return this.wrap;
		},
		init: function() {
			if (!this.get('mode')) {
				this.set('mode', S.ContentArea.mode);
			}
			//// Not working without fixing bubbling of events from editing fields
			// $(document).keyup(function(event) {
			// 	console.log('key press', event, event.srcElement)
			// 	if (event.keyCode === 13 && event.srcElement === window.document) {
			// 		this.toggle_modes();
			// 	}
			// }.bind(this));
		},
		set_mode: function(mode) {
			this.set('mode', mode);
			this.mode_switch.text(this.opposite_mode(mode));
		},
		toggle_modes: function() {
			this.set_mode(this.opposite_mode(this.get('mode')));
		},
		opposite_mode: function(to_mode) {
			if (to_mode === 'preview') {
				return 'edit';
			} else if (to_mode === 'edit') {
				return 'preview';
			}
		},
		publishing_started: function() {
			this.publish_button.publishing_started();
		},
		location_changed: function(new_location) {
			document.title = "Editing: '{title}'".replace("{title}", new_location.title);
			this.set('location', new_location);
			this.update_navigation();
		},
		update_navigation: function() {
			var nodes = [];
			var location = this.get('location');
			var ancestors = location.ancestors;
			var root, is_root = false, root_node, children_node, current_node;
			if (ancestors.length === 0) {
				root = location;
				is_root = true;
			} else {
				root = ancestors.shift();
			}
			root_node = new RootNode(root);
			nodes.push(root_node);
			for (var i=0, ii=ancestors.length; i < ii; i++) {
				var page = ancestors[i];
				var node = new AncestorNode(page)
				nodes.push(node);
			};
			if (!is_root) {
				current_node = new CurrentNode(location)
				nodes.push(current_node);
			} else {
				current_node = root_node;
			}
			//if (location.children.length > 0) {
				children_node = new ChildrenNode(location.children);
				nodes.push(children_node);
			//}
			$('li:gt(0)', this.location).remove();
			// this.location.empty();
			for (var i = 0, ii = nodes.length; i < ii; i++) {
				var node = nodes[i];
				this.location.append(node.element())
			}
			this.navigation_current = current_node;
			S.Editing.watch('page', function(page) {
				if (page) {
					page.watch('new_entry', function(new_entry) {
						var entry = new_entry.entry, position = new_entry.position;
						if (entry.content.is_page) {
							console.log('new page', entry.title_field().value(), position);
							children_node.add_page(entry.content, position);
						}
					});
					page.watch('removed_entry', function(content) {
						console.log('removed_entry', content)
						// var content = entry.content;
						if (content.content.is_page) {
							console.log('removed page', content.title_field().value());
							children_node.remove_page(content);
						}
					});
					page.title_field().watch('value', function(title) {
						current_node.set_title(title);
					});
				}
			})
		}
	});
	return TopBar;
})(jQuery, Spontaneous);



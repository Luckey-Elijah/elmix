import 'dart:async';
import 'dart:convert';

import 'package:elmix_admin/src/admin_control_plane.dart';
import 'package:elmix_admin/src/admin_ui/admin_session_store.dart';
import 'package:elmix_admin/src/admin_ui/record_form_values.dart';
import 'package:elmix_engine/elmix_engine.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The browser-side Admin Control Plane application.
class AdminApp extends StatefulComponent {
  /// Creates the Admin Control Plane application.
  const AdminApp({
    required this.controlPlane,
    required this.sessions,
    super.key,
  });

  /// Admin API application boundary used by the UI.
  final AdminControlPlane controlPlane;

  /// Session-scoped bearer-token storage.
  final AdminSessionStore sessions;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  final _accessRuleExpressions = <CollectionOperation, String>{};
  var _adminAccounts = const <AdminAccountView>[];
  final _recordRawValues = <String, String>{};
  var _email = '';
  var _newCollectionName = '';
  var _newAdminEmail = '';
  var _newAdminPassword = '';
  var _adminAccountPassword = '';
  var _password = '';
  var _creatingAdminAccount = false;
  var _creatingCollection = false;
  var _fieldName = '';
  var _fieldRequired = false;
  var _fieldTargetCollection = '';
  FieldType _fieldType = .text;
  var _isAuthCollection = false;
  var _signedIn = false;
  var _signingIn = false;
  var _savingField = false;
  var _savingRecord = false;
  var _schemas = const <CollectionSchema>[];
  var _showingAdminAccounts = false;
  var _records = const <Record>[];
  SchemaField? _editingField;
  AdminAccountView? _editingAdminAccount;
  Record? _editingRecord;
  CollectionSchema? _selectedSchema;
  var _recordId = '';
  var _recordsLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final token = component.sessions.readBearerToken();
    component.controlPlane.api.bearerToken = token;
    _signedIn = token != null;
    if (_signedIn) {
      unawaited(_loadCollectionSchemas());
    }
  }

  @override
  Component build(BuildContext context) {
    return main_([
      const header([
        h1([Component.text('Elmix Admin Control Plane')]),
      ]),
      if (_signedIn)
        _showingAdminAccounts
            ? _buildAdminAccounts()
            : _selectedSchema == null
            ? _buildCollectionSchemaList()
            : _buildCollectionSchemaDetail(_selectedSchema!)
      else
        section([
          const h2([Component.text('Sign in to Elmix')]),
          input<String>(
            type: InputType.email,
            name: 'email',
            onInput: (value) => _email = value,
          ),
          input<String>(
            type: InputType.password,
            name: 'password',
            onInput: (value) => _password = value,
          ),
          if (_error != null) p([Component.text(_error!)]),
          button(
            const [Component.text('Sign in')],
            disabled: _signingIn,
            onClick: _signIn,
          ),
        ]),
    ]);
  }

  Component _buildCollectionSchemaList() {
    return section([
      const h2([Component.text('Collection Schemas')]),
      button(
        const [Component.text('Admin Accounts')],
        type: ButtonType.button,
        onClick: () => unawaited(_openAdminAccounts()),
      ),
      if (_error != null) p([Component.text(_error!)]),
      const h3([Component.text('Create Collection Schema')]),
      const label(
        htmlFor: 'collection-name',
        [Component.text('Collection name')],
      ),
      input<String>(
        id: 'collection-name',
        type: InputType.text,
        name: 'collection-name',
        value: _newCollectionName,
        onInput: (value) => _newCollectionName = value,
      ),
      button(
        const [Component.text('Create collection')],
        type: ButtonType.button,
        disabled: _creatingCollection,
        onClick: () => unawaited(_createCollectionSchema()),
      ),
      ul([
        for (final schema in _schemas)
          li([
            button(
              [Component.text(schema.name)],
              type: ButtonType.button,
              onClick: () => _openCollectionSchema(schema),
            ),
          ]),
      ]),
    ]);
  }

  Component _buildAdminAccounts() {
    return section([
      button(
        const [Component.text('Back to Collection Schemas')],
        type: ButtonType.button,
        onClick: () {
          setState(() {
            _showingAdminAccounts = false;
            _error = null;
          });
        },
      ),
      const h2([Component.text('Admin Accounts')]),
      if (_error != null) p([Component.text(_error!)]),
      const h3([Component.text('Create Admin Account')]),
      const label(
        htmlFor: 'admin-account-email',
        [Component.text('Admin Account email')],
      ),
      input<String>(
        id: 'admin-account-email',
        type: InputType.email,
        name: 'admin-account-email',
        value: _newAdminEmail,
        onInput: (value) => _newAdminEmail = value,
      ),
      const label(
        htmlFor: 'admin-account-password',
        [Component.text('Admin Account password')],
      ),
      input<String>(
        id: 'admin-account-password',
        type: InputType.password,
        name: 'admin-account-password',
        value: _newAdminPassword,
        onInput: (value) => _newAdminPassword = value,
      ),
      button(
        const [Component.text('Save Admin Account')],
        type: ButtonType.button,
        disabled: _creatingAdminAccount,
        onClick: () => unawaited(_createAdminAccount()),
      ),
      if (_editingAdminAccount != null) ...[
        h3([
          Component.text(
            'Set password for ${_editingAdminAccount!.email}',
          ),
        ]),
        const label(
          htmlFor: 'changed-admin-account-password',
          [Component.text('New Admin Account password')],
        ),
        input<String>(
          id: 'changed-admin-account-password',
          type: InputType.password,
          name: 'changed-admin-account-password',
          value: _adminAccountPassword,
          onInput: (value) => _adminAccountPassword = value,
        ),
        button(
          const [Component.text('Save Admin Account Password')],
          type: ButtonType.button,
          onClick: () => unawaited(_changeAdminAccountPassword()),
        ),
      ],
      ul([
        for (final account in _adminAccounts)
          li([
            Component.text(account.email),
            button(
              const [Component.text('Change Admin Account Password')],
              type: ButtonType.button,
              onClick: () {
                setState(() {
                  _editingAdminAccount = account;
                  _adminAccountPassword = '';
                  _error = null;
                });
              },
            ),
            button(
              const [Component.text('Delete Admin Account')],
              type: ButtonType.button,
              onClick: () => unawaited(_deleteAdminAccount(account)),
            ),
          ]),
      ]),
    ]);
  }

  Component _buildCollectionSchemaDetail(CollectionSchema schema) {
    return section([
      button(
        const [Component.text('Back to Collection Schemas')],
        type: ButtonType.button,
        onClick: () {
          setState(() {
            _selectedSchema = null;
            _error = null;
          });
        },
      ),
      h2([Component.text('${schema.name} Collection Schema')]),
      if (_error != null) p([Component.text(_error!)]),
      const h3([Component.text('Collection Settings')]),
      const label(
        htmlFor: 'is-auth-collection',
        [Component.text('Authentication Collection')],
      ),
      input<bool>(
        id: 'is-auth-collection',
        type: InputType.checkbox,
        checked: _isAuthCollection,
        onChange: (value) => _isAuthCollection = value,
      ),
      button(
        const [Component.text('Save Collection Schema')],
        type: ButtonType.button,
        onClick: () => unawaited(_saveCollectionSchema()),
      ),
      button(
        const [Component.text('Delete Collection Schema')],
        type: ButtonType.button,
        onClick: () => unawaited(_deleteCollectionSchema(schema)),
      ),
      const h3([Component.text('Schema Fields')]),
      h4([
        Component.text(
          _editingField == null ? 'Create Schema Field' : 'Edit Schema Field',
        ),
      ]),
      const label(
        htmlFor: 'field-name',
        [Component.text('Field name')],
      ),
      input<String>(
        id: 'field-name',
        type: InputType.text,
        name: 'field-name',
        value: _fieldName,
        disabled: _editingField != null,
        onInput: (value) => _fieldName = value,
      ),
      const label(
        htmlFor: 'field-type',
        [Component.text('Field type')],
      ),
      select(
        id: 'field-type',
        name: 'field-type',
        value: _fieldType.name,
        onChange: (values) {
          setState(() {
            _fieldType = FieldType.values.byName(values.single);
          });
        },
        [
          for (final type in FieldType.values)
            option([Component.text(type.name)], value: type.name),
        ],
      ),
      const label(
        htmlFor: 'field-required',
        [Component.text('Required')],
      ),
      input<bool>(
        id: 'field-required',
        type: InputType.checkbox,
        checked: _fieldRequired,
        onChange: (value) => _fieldRequired = value,
      ),
      if (_fieldType == .relation) ...[
        const label(
          htmlFor: 'field-target-collection',
          [Component.text('Target Collection Schema')],
        ),
        input<String>(
          id: 'field-target-collection',
          type: InputType.text,
          name: 'field-target-collection',
          value: _fieldTargetCollection,
          onInput: (value) => _fieldTargetCollection = value,
        ),
      ],
      button(
        const [Component.text('Save Schema Field')],
        type: ButtonType.button,
        disabled: _savingField,
        onClick: () => unawaited(_saveSchemaField()),
      ),
      ul([
        for (final field in schema.fields)
          li([
            Component.text('${field.name} (${field.type.name})'),
            button(
              const [Component.text('Edit Schema Field')],
              type: ButtonType.button,
              onClick: () => _beginSchemaFieldEdit(field),
            ),
            if (field.removable)
              button(
                const [Component.text('Delete Schema Field')],
                type: ButtonType.button,
                onClick: () => unawaited(_deleteSchemaField(field)),
              ),
          ]),
      ]),
      const h3([Component.text('Records')]),
      button(
        const [Component.text('Load Records')],
        type: ButtonType.button,
        onClick: () => unawaited(_loadRecords(schema)),
      ),
      h4([
        Component.text(
          _editingRecord == null ? 'Create Record' : 'Edit Record',
        ),
      ]),
      const label(
        htmlFor: 'record-id',
        [Component.text('Record Identifier')],
      ),
      input<String>(
        id: 'record-id',
        type: InputType.text,
        name: 'record-id',
        value: _recordId,
        disabled: _editingRecord != null,
        onInput: (value) => _recordId = value,
      ),
      for (final field in schema.fields)
        if (field.systemRole != .recordIdentifier) _buildRecordField(field),
      button(
        const [Component.text('Save Record')],
        type: ButtonType.button,
        disabled: _savingRecord,
        onClick: () => unawaited(_saveRecord(schema)),
      ),
      if (_recordsLoaded)
        ul([
          for (final record in _records)
            li([
              Component.text(record.id.value),
              button(
                const [Component.text('View Record')],
                type: ButtonType.button,
                onClick: () => unawaited(_viewRecord(schema, record)),
              ),
              button(
                const [Component.text('Delete Record')],
                type: ButtonType.button,
                onClick: () => unawaited(_deleteRecord(schema, record)),
              ),
            ]),
        ]),
      const h3([Component.text('Access Rules')]),
      for (final operation in CollectionOperation.values) ...[
        label(
          htmlFor: 'access-rule-${operation.name}',
          [
            Component.text(_accessRuleLabel(operation)),
          ],
        ),
        textarea(
          [Component.text(_accessRuleExpressions[operation] ?? '')],
          id: 'access-rule-${operation.name}',
          name: 'access-rule-${operation.name}',
          rows: 3,
          onInput: (value) => _accessRuleExpressions[operation] = value,
        ),
      ],
      button(
        const [Component.text('Save Access Rules')],
        type: ButtonType.button,
        onClick: () => unawaited(_saveAccessRules()),
      ),
    ]);
  }

  Component _buildRecordField(SchemaField field) {
    final labelText = '${field.name} (${field.type.name})';
    if (field.type == .json) {
      return Component.fragment([
        label(
          htmlFor: 'record-${field.name}',
          [Component.text(labelText)],
        ),
        textarea(
          [Component.text(_recordRawValues[field.name] ?? '')],
          id: 'record-${field.name}',
          name: 'record-${field.name}',
          rows: 5,
          onInput: (value) => _recordRawValues[field.name] = value,
        ),
      ]);
    }
    if (field.type == .bool) {
      return Component.fragment([
        label(
          htmlFor: 'record-${field.name}',
          [Component.text(labelText)],
        ),
        input<bool>(
          id: 'record-${field.name}',
          type: InputType.checkbox,
          checked: _recordRawValues[field.name] == 'true',
          onChange: (value) => _recordRawValues[field.name] = '$value',
        ),
      ]);
    }
    return Component.fragment([
      label(
        htmlFor: 'record-${field.name}',
        [Component.text(labelText)],
      ),
      input<String>(
        id: 'record-${field.name}',
        type: field.type == .password ? InputType.password : InputType.text,
        name: 'record-${field.name}',
        value: _recordRawValues[field.name] ?? '',
        onInput: (value) => _recordRawValues[field.name] = value,
      ),
    ]);
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final session = await component.controlPlane.login(
        email: _email,
        password: _password,
      );
      component.sessions.saveBearerToken(session.token);
      setState(() {
        _signedIn = true;
        _signingIn = false;
      });
      await _loadCollectionSchemas();
    } on AdminApiException catch (error) {
      setState(() {
        _error = error.message ?? 'Sign in failed.';
        _signingIn = false;
      });
    }
  }

  Future<void> _loadCollectionSchemas() async {
    try {
      final schemas = await component.controlPlane.listCollectionSchemas();
      if (!mounted) {
        return;
      }
      setState(() {
        _schemas = <CollectionSchema>[
          for (final schema in schemas)
            if (schema.name != '_admins') schema,
        ];
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not load Collection Schemas.';
      });
    }
  }

  Future<void> _createCollectionSchema() async {
    final name = _newCollectionName.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'A Collection Schema name is required.';
      });
      return;
    }

    setState(() {
      _creatingCollection = true;
      _error = null;
    });
    try {
      final schema = await component.controlPlane.createCollectionSchema(
        CollectionSchema(
          name: name,
          fields: CollectionSchema.defaultFields(),
          accessRules: const <CollectionOperation, AccessRule>{},
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _schemas = <CollectionSchema>[..._schemas, schema];
        _newCollectionName = '';
        _creatingCollection = false;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _creatingCollection = false;
        _error = error.message ?? 'Could not create the Collection Schema.';
      });
    }
  }

  void _beginSchemaFieldEdit(SchemaField field) {
    setState(() {
      _editingField = field;
      _fieldName = field.name;
      _fieldType = field.type;
      _fieldRequired = field.required;
      _fieldTargetCollection = field.targetCollection ?? '';
      _error = null;
    });
  }

  Future<void> _saveSchemaField() async {
    final schema = _selectedSchema!;
    final name = _fieldName.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'A Schema Field name is required.';
      });
      return;
    }
    if (_fieldType == .relation && _fieldTargetCollection.trim().isEmpty) {
      setState(() {
        _error = 'A Relation Field requires a target Collection Schema.';
      });
      return;
    }

    final existing = _editingField;
    final field = SchemaField(
      name: name,
      type: _fieldType,
      required: _fieldRequired,
      removable: existing?.removable ?? true,
      systemRole: existing?.systemRole ?? .none,
      targetCollection: _fieldType == .relation
          ? _fieldTargetCollection.trim()
          : null,
    );
    setState(() {
      _savingField = true;
      _error = null;
    });
    try {
      final updated = existing == null
          ? await component.controlPlane.createSchemaField(
              collection: schema.name,
              field: field,
            )
          : await component.controlPlane.updateSchemaField(
              collection: schema.name,
              field: field,
            );
      if (!mounted) {
        return;
      }
      _replaceSelectedSchema(updated);
      setState(() {
        _editingField = null;
        _fieldName = '';
        _fieldType = .text;
        _fieldRequired = false;
        _fieldTargetCollection = '';
        _savingField = false;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _savingField = false;
        _error = error.message ?? 'Could not save the Schema Field.';
      });
    }
  }

  Future<void> _deleteSchemaField(SchemaField field) async {
    final schema = _selectedSchema!;
    try {
      final updated = await component.controlPlane.deleteSchemaField(
        collection: schema.name,
        field: field.name,
      );
      if (!mounted) {
        return;
      }
      _replaceSelectedSchema(updated);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not delete the Schema Field.';
      });
    }
  }

  void _openCollectionSchema(CollectionSchema schema) {
    setState(() {
      _selectedSchema = schema;
      _isAuthCollection = schema.isAuthCollection;
      _accessRuleExpressions
        ..clear()
        ..addEntries(
          schema.accessRules.entries.map(
            (entry) => MapEntry(entry.key, entry.value.expression),
          ),
        );
      _clearRecordForm();
      _records = const <Record>[];
      _recordsLoaded = false;
      _error = null;
    });
  }

  Future<void> _openAdminAccounts() async {
    setState(() {
      _showingAdminAccounts = true;
      _error = null;
    });
    try {
      final accounts = await component.controlPlane.listAdminAccounts();
      if (!mounted) {
        return;
      }
      setState(() {
        _adminAccounts = accounts;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not load Admin Accounts.';
      });
    }
  }

  Future<void> _createAdminAccount() async {
    final email = _newAdminEmail.trim();
    if (email.isEmpty || _newAdminPassword.isEmpty) {
      setState(() {
        _error = 'An Admin Account email and password are required.';
      });
      return;
    }
    setState(() {
      _creatingAdminAccount = true;
      _error = null;
    });
    try {
      final account = await component.controlPlane.createAdminAccount(
        email: email,
        password: _newAdminPassword,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _adminAccounts = <AdminAccountView>[..._adminAccounts, account];
        _newAdminEmail = '';
        _newAdminPassword = '';
        _creatingAdminAccount = false;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _creatingAdminAccount = false;
        _error = error.message ?? 'Could not create the Admin Account.';
      });
    }
  }

  Future<void> _changeAdminAccountPassword() async {
    final account = _editingAdminAccount!;
    if (_adminAccountPassword.isEmpty) {
      setState(() {
        _error = 'An Admin Account password is required.';
      });
      return;
    }
    try {
      final changed = await component.controlPlane.changeAdminAccountPassword(
        id: account.id,
        password: _adminAccountPassword,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _adminAccounts = <AdminAccountView>[
          for (final existing in _adminAccounts)
            if (existing.id == changed.id) changed else existing,
        ];
        _editingAdminAccount = null;
        _adminAccountPassword = '';
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error =
            error.message ?? 'Could not change the Admin Account password.';
      });
    }
  }

  Future<void> _deleteAdminAccount(AdminAccountView account) async {
    try {
      await component.controlPlane.deleteAdminAccount(account.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _adminAccounts = <AdminAccountView>[
          for (final existing in _adminAccounts)
            if (existing.id != account.id) existing,
        ];
        if (_editingAdminAccount?.id == account.id) {
          _editingAdminAccount = null;
          _adminAccountPassword = '';
        }
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not delete the Admin Account.';
      });
    }
  }

  bool _handleUnauthorizedSession(AdminApiException error) {
    if (error.statusCode != 401) {
      return false;
    }
    component.sessions.clearBearerToken();
    component.controlPlane.api.clearBearerToken();
    setState(() {
      _creatingAdminAccount = false;
      _creatingCollection = false;
      _savingField = false;
      _savingRecord = false;
      _signedIn = false;
      _selectedSchema = null;
      _error = error.message ?? 'Your Admin session has expired.';
    });
    return true;
  }

  Future<void> _saveCollectionSchema() async {
    final schema = _selectedSchema!;
    try {
      final updated = await component.controlPlane.updateCollectionSchema(
        CollectionSchema(
          name: schema.name,
          isAuthCollection: _isAuthCollection,
          fields: schema.fields,
          accessRules: schema.accessRules,
        ),
      );
      if (!mounted) {
        return;
      }
      _replaceSelectedSchema(updated);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not save the Collection Schema.';
      });
    }
  }

  Future<void> _saveAccessRules() async {
    final schema = _selectedSchema!;
    final accessRules = <CollectionOperation, AccessRule>{
      for (final entry in _accessRuleExpressions.entries)
        if (entry.value.trim().isNotEmpty)
          entry.key: AccessRule(entry.value.trim()),
    };
    try {
      final updated = await component.controlPlane.updateAccessRules(
        collection: schema.name,
        accessRules: accessRules,
      );
      if (!mounted) {
        return;
      }
      _replaceSelectedSchema(updated);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not save Access Rules.';
      });
    }
  }

  Future<void> _loadRecords(CollectionSchema schema) async {
    try {
      final page = await component.controlPlane.listRecords(schema.name);
      if (!mounted) {
        return;
      }
      setState(() {
        _records = page.items;
        _recordsLoaded = true;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not load Records.';
      });
    }
  }

  Future<void> _saveRecord(CollectionSchema schema) async {
    final id = _recordId.trim();
    if (id.isEmpty) {
      setState(() {
        _error = 'A Record Identifier is required.';
      });
      return;
    }

    final Map<String, Object?> data;
    try {
      data = RecordFormValues.parse(
        fields: schema.fields,
        rawValues: _recordRawValues,
        allowEmptyFields: _editingRecord == null
            ? const <String>{}
            : <String>{
                for (final field in schema.fields)
                  if (field.type == .password) field.name,
              },
      );
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
      });
      return;
    }

    final record = Record(
      collection: schema.name,
      id: RecordIdentifier(id),
      data: data,
    );
    setState(() {
      _savingRecord = true;
      _error = null;
    });
    try {
      final saved = _editingRecord == null
          ? await component.controlPlane.createRecord(record)
          : await component.controlPlane.updateRecord(record);
      if (!mounted) {
        return;
      }
      setState(() {
        _records = <Record>[
          for (final existing in _records)
            if (existing.id == saved.id) saved else existing,
          if (!_records.any((existing) => existing.id == saved.id)) saved,
        ];
        _recordsLoaded = true;
        _clearRecordForm();
        _savingRecord = false;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _savingRecord = false;
        _error = error.message ?? 'Could not save the Record.';
      });
    }
  }

  Future<void> _viewRecord(CollectionSchema schema, Record record) async {
    try {
      final viewed = await component.controlPlane.viewRecord(
        collection: schema.name,
        id: record.id,
      );
      if (!mounted) {
        return;
      }
      _beginRecordEdit(schema, viewed);
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not load the Record.';
      });
    }
  }

  void _beginRecordEdit(CollectionSchema schema, Record record) {
    setState(() {
      _editingRecord = record;
      _recordId = record.id.value;
      _recordRawValues
        ..clear()
        ..addEntries(
          schema.fields
              .where((field) => field.systemRole != .recordIdentifier)
              .map(
                (field) => MapEntry(
                  field.name,
                  _recordRawValue(field, record.data[field.name]),
                ),
              ),
        );
      _error = null;
    });
  }

  Future<void> _deleteRecord(CollectionSchema schema, Record record) async {
    try {
      await component.controlPlane.deleteRecord(
        collection: schema.name,
        id: record.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records = <Record>[
          for (final existing in _records)
            if (existing.id != record.id) existing,
        ];
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not delete the Record.';
      });
    }
  }

  void _clearRecordForm() {
    _editingRecord = null;
    _recordId = '';
    _recordRawValues.clear();
  }

  String _recordRawValue(SchemaField field, Object? value) {
    if (value == null) {
      return '';
    }
    return switch (field.type) {
      .password => '',
      .json => jsonEncode(value),
      .date when value is DateTime => value.toIso8601String(),
      _ => '$value',
    };
  }

  Future<void> _deleteCollectionSchema(CollectionSchema schema) async {
    try {
      await component.controlPlane.deleteCollectionSchema(schema.name);
      if (!mounted) {
        return;
      }
      setState(() {
        _schemas = <CollectionSchema>[
          for (final existing in _schemas)
            if (existing.name != schema.name) existing,
        ];
        _selectedSchema = null;
      });
    } on AdminApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (_handleUnauthorizedSession(error)) {
        return;
      }
      setState(() {
        _error = error.message ?? 'Could not delete the Collection Schema.';
      });
    }
  }

  void _replaceSelectedSchema(CollectionSchema schema) {
    setState(() {
      _selectedSchema = schema;
      _schemas = <CollectionSchema>[
        for (final existing in _schemas)
          if (existing.name == schema.name) schema else existing,
      ];
    });
  }

  String _accessRuleLabel(CollectionOperation operation) {
    final name = operation.name;
    return '${name[0].toUpperCase()}${name.substring(1)} Access Rule';
  }
}

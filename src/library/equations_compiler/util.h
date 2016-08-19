/*
Copyright (c) 2016 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Author: Leonardo de Moura
*/
#pragma once
#include "library/type_context.h"
namespace lean {
[[ noreturn ]] void throw_ill_formed_eqns();

/** \brief Helper class for modifying/updating an equations-expression.

    \remark The equations macro is awkward to use since it is a leftover
    from the Lean2 equation compiler. The class tries to hide the problems
    with this data-structure. We cannot change the equations-macro
    until we remove the old equations compiler.

    TODO(Leo): as soon as we remove the legacy code from Lean2, this
    class will be much simpler. */
class unpack_eqns {
    type_context::tmp_locals m_locals;
    expr                     m_src;
    buffer<expr>             m_fns;
    /* m_arity[i] contains the number of arguments for each equation lhs
       for m_fns[i].
       \remark m_arity.size() == m_fns.size().
       \remark The information stored in this field is ignore by repack. */
    buffer<unsigned>         m_arity;
    /* m_eqns[i] are the equations for m_fns[i].
       \remark m_eqs.size() == m_fns.size(). */
    buffer<buffer<expr>>     m_eqs;
public:
    /** \brief Extract the data stored in the equations-expression \c e.
        \pre is_equations(e) */
    unpack_eqns(type_context & ctx, expr const & e);
    /** \brief Re-build an equations-expression using the information
        stored at m_fns and m_eqs. */
    expr repack();

    /** Update the type of the function with the given idx.
        \remark The equations are not updated. They still reference the old function. */
    expr update_fn_type(unsigned fidx, expr const & type);

    unsigned get_num_fns() const { return m_fns.size(); }
    expr const & get_fn(unsigned fidx) const { return m_fns[fidx]; }
    buffer<expr> & get_eqns_of(unsigned fidx) { return m_eqs[fidx]; }
    buffer<expr> const & get_eqns_of(unsigned fidx) const { return m_eqs[fidx]; }
    unsigned get_arity_of(unsigned fidx) const { return m_arity[fidx]; }
};

/** \brief Helper class for unpacking a single equation nested in a equations expression. */
class unpack_eqn {
    expr                     m_src;
    type_context::tmp_locals m_locals;
    bool                     m_modified_vars{false};
    buffer<expr>             m_vars;
    expr                     m_nested_src;
    expr                     m_lhs;
    expr                     m_rhs;
public:
    unpack_eqn(type_context & ctx, expr const & eqn);
    expr add_var(name const & n, expr const & type);
    buffer<expr> const & get_vars() { return m_vars; }
    expr & lhs() { return m_lhs; }
    expr & rhs() { return m_rhs; }
    expr repack();
};

/** \brief Interface object for providing extra functionality
    required by the equation compiler from the environment.

    For example, it abstracts the inductive datatype API.
    So, if we add new forms of inductive datatype, we need
    to change this class. */
class eqns_env_interface {
    environment m_env;
public:
    eqns_env_interface(environment const & env):m_env(env) {}
    eqns_env_interface(type_context const & ctx):m_env(ctx.env()) {}

    bool is_inductive(name const & n) const;
    bool is_inductive(expr const & e) const;
    optional<name> is_constructor(expr const & e) const;
    unsigned get_inductive_num_params(name const & n) const;
    unsigned get_inductive_num_indices(name const & n) const;
};

/** \brief Return true iff \c e is recursive. That is, some equation
    in the rhs has a reference to a function being defined by the
    equations. */
bool is_recursive_eqns(type_context & ctx, expr const & e);
}
